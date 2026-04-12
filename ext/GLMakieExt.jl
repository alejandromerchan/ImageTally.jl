module GLMakieExt

using GLMakie
using FileIO
using ColorTypes
import ImageTally
using ImageTally:
    Tag,
    CountSession,
    CountPoint,
    default_tags,
    load_session,
    new_session,
    add_point!,
    delete_point!,
    move_point!,
    find_nearest_point,
    count_by_tag,
    total_count,
    set_active_tag!,
    set_marker_size!,
    save_session,
    export_csv

# -----------------------------------------------------------------------
# Override ImageTally.launch_counter
# -----------------------------------------------------------------------

"""
    ImageTally.launch_counter(image_path; session=nothing) -> (Figure, CountSession)

Launch the ImageTally GUI using GLMakie.

# Arguments
- `image_path::String`: Path to the image to count.
- `session::Union{String,Nothing}`: Path to a `.toml` session file to resume.
  Defaults to `nothing` (creates a new session).

# Returns
`(fig, sess)` — the Makie `Figure` and the live `CountSession`. The window
remains interactive while the Julia session is running.

# Usage
```julia
using GLMakie, ImageTally
fig, sess = launch_counter("moths.jpg")
fig, sess = launch_counter("moths.jpg"; session="moths_session.toml")
```
"""
function ImageTally.launch_counter(
    image_path::String;
    session::Union{String,Nothing} = nothing,
)
    isfile(image_path) || throw(ArgumentError("Image file not found: $image_path"))

    img = FileIO.load(image_path)
    # size(img) == (height, width) for a loaded raster image
    h, w = size(img)

    sess = if !isnothing(session)
        load_session(session)
    else
        new_session(image_path, w, h)
    end

    return _launch_gui(sess, img)
end

"""
    ImageTally.launch_counter(sess::CountSession) -> (Figure, CountSession)

Launch the ImageTally GUI for a pre-built `CountSession`. The image is loaded
from `sess.image_path`.

# Usage
```julia
using GLMakie, ImageTally
sess = new_session("moths.jpg"; tags = [
    Tag("egg", :red, :circle),
    Tag("parasitized", :blue, :utriangle),
])
fig, sess = launch_counter(sess)
```
"""
function ImageTally.launch_counter(sess::CountSession)
    isfile(sess.image_path) ||
        throw(ArgumentError("Image file not found: $(sess.image_path)"))
    img = FileIO.load(sess.image_path)
    return _launch_gui(sess, img)
end

"""
    ImageTally.new_session(image_path; tags=default_tags()) -> CountSession

Create a new counting session, reading image dimensions automatically from the file.

# Arguments
- `image_path::String`: Path to the image file.
- `tags::Vector{Tag}`: Tags to use for counting. Defaults to `[Tag("object", :red, :circle)]`.

# Usage
```julia
using GLMakie, ImageTally
sess = new_session("moths.jpg")
sess = new_session("moths.jpg"; tags = [
    Tag("egg", :red, :circle),
    Tag("parasitized", :blue, :utriangle),
])
fig, sess = launch_counter(sess)
```
"""
function ImageTally.new_session(image_path::String; tags::Vector{Tag} = default_tags())
    isfile(image_path) || throw(ArgumentError("Image file not found: $image_path"))
    img = FileIO.load(image_path)
    h, w = size(img)
    return new_session(image_path, w, h; tags)
end

# -----------------------------------------------------------------------
# Zoom limit helpers (pure functions — no Makie dependency, testable)
# -----------------------------------------------------------------------

"""
    _zoom_in_limits(xmin, xmax, ymin, ymax, factor=1.5)

Return `(xmin, xmax, ymin, ymax)` for a zoom-in step of `factor` centered on
the current view. Both axes shrink by `factor`.
"""
function _zoom_in_limits(xmin::Real, xmax::Real, ymin::Real, ymax::Real, factor::Real = 1.5)
    cx = (xmin + xmax) / 2
    cy = (ymin + ymax) / 2
    hw = (xmax - xmin) / (2 * factor)
    hh = (ymax - ymin) / (2 * factor)
    return (cx - hw, cx + hw, cy - hh, cy + hh)
end

"""
    _zoom_out_limits(xmin, xmax, ymin, ymax, img_w, img_h, factor=1.5)

Return `(xmin, xmax, ymin, ymax)` for a zoom-out step of `factor` centered on
the current view, clamped to the image bounds `[0.5, img_w+0.5] × [0.5, img_h+0.5]`.
"""
function _zoom_out_limits(
    xmin::Real,
    xmax::Real,
    ymin::Real,
    ymax::Real,
    img_w::Real,
    img_h::Real,
    factor::Real = 1.5,
)
    cx = (xmin + xmax) / 2
    cy = (ymin + ymax) / 2
    new_hw = (xmax - xmin) * factor / 2
    new_hh = (ymax - ymin) * factor / 2
    return (
        max(0.5, cx - new_hw),
        min(img_w + 0.5, cx + new_hw),
        max(0.5, cy - new_hh),
        min(img_h + 0.5, cy + new_hh),
    )
end

# -----------------------------------------------------------------------
# Internal GUI builder
# -----------------------------------------------------------------------

"""
    _normalize_image(img) -> AbstractMatrix

Ensure `img` is a 2D matrix suitable for Makie's `image!`.

Some TIF loaders (e.g. TiffImages) return a 3D `Array{<:Colorant, 3}` with
shape `(H, W, 1)` even for single-channel files, or `(H, W, C)` for
multi-channel raw arrays.  Makie requires an `AbstractMatrix`, so we squeeze
or reconstruct here.
"""
function _normalize_image(img::AbstractArray)
    ndims(img) == 2 && return img
    ndims(img) != 3 && error("Cannot display image with $(ndims(img)) dimensions")
    H, W, C = size(img)
    # Element type is already a full Colorant (Gray, RGB, …): the 3rd dimension
    # is spurious (size-1 channel dim from the TIF loader).  Slice it off.
    if eltype(img) <: Colorant
        return img[:, :, 1]
    end
    # Raw numeric channels-last layout
    C == 1 && return img[:, :, 1]
    C == 3 && return [RGB(img[i, j, 1], img[i, j, 2], img[i, j, 3]) for i = 1:H, j = 1:W]
    C == 4 && return [
        RGBA(img[i, j, 1], img[i, j, 2], img[i, j, 3], img[i, j, 4]) for i = 1:H, j = 1:W
    ]
    # Fallback: first channel only
    return img[:, :, 1]
end

function _launch_gui(sess::CountSession, img)
    img = _normalize_image(img)
    n_tags = length(sess.tags)
    h = sess.image_height
    w = sess.image_width

    # ── Figure & layout ──────────────────────────────────────────────────
    aspect_ratio = w / h
    panel_width = 280
    canvas_height = 800
    canvas_width = round(Int, canvas_height * aspect_ratio)
    fig_width = canvas_width + panel_width
    # figure_padding=0 ensures the layout area equals the figure size exactly,
    # so canvas_width = canvas_height * (w/h) is accurate with no padding offset.
    fig = Figure(size = (fig_width, canvas_height), figure_padding = 0)

    # ── Image axis ───────────────────────────────────────────────────────
    # Flip image rows so the top row displays at the top without yreversed=true.
    # yreversed=true causes is_mouseinside to misreport the axis boundary in
    # GLMakie, so we keep a standard (y-up) axis and compensate in coordinates.
    img_display = reverse(img, dims = 1)
    # DataAspect enforces the data-unit aspect ratio regardless of axis pixel size,
    # preventing squishing when canvas proportions are slightly off.
    ax = Axis(fig[1, 1]; aspect = DataAspect())
    hidespines!(ax)
    hidedecorations!(ax)
    # image!(ax, M) maps first dim of M → x-axis, second dim → y-axis.
    # img_display is (h, w), so without transposing, x gets h samples and y gets w —
    # the image is transposed in axis space and limits based on (w, h) cut off the top.
    # PermutedDimsArray transposes lazily (no copy) so first dim becomes w (columns → x)
    # and second becomes h (rows → y), giving x ∈ [0.5, w+0.5], y ∈ [0.5, h+0.5].
    image!(ax, PermutedDimsArray(img_display, (2, 1)))
    ax.limits[] = (0.5, Float64(w) + 0.5, 0.5, Float64(h) + 0.5)

    # Deregister built-in left-click/drag interactions so they don't
    # interfere with add-point (click) and move-point (drag).
    # Scroll-zoom and limit-reset (R key) are kept.
    for name in (:rectanglezoom, :dragpan)
        try
            deregister_interaction!(ax, name)
        catch e
            @warn "Could not deregister interaction $name" exception = e
        end
    end

    # ── Control panel ────────────────────────────────────────────────────
    # Column 1 is fixed; column 2 fills the remainder (= panel_width) implicitly.
    # colsize! on column 2 would error here because no content has been placed
    # in it yet — GridLayoutBase only registers a column when content is added.
    panel = fig[1, 2]
    colsize!(fig.layout, 1, Fixed(canvas_width))

    # ── Observables ──────────────────────────────────────────────────────
    tag_pts_obs = [Observable(Point2f[]) for _ = 1:n_tags]
    count_obs = [Observable(0) for _ = 1:n_tags]
    total_obs = Observable(0)
    active_tag_obs = Observable(sess.active_tag)
    status_obs = Observable(" ")

    # ── Scatter plot per tag ─────────────────────────────────────────────
    # markersize is set as a plain value and updated via plot.markersize[],
    # not via a bound Observable — reactive markersize breaks hit detection
    # after the slider is moved.
    scatter_plots = map(enumerate(sess.tags)) do (i, tag)
        scatter!(
            ax,
            tag_pts_obs[i];
            color = tag.color,
            marker = tag.marker,
            markersize = sess.marker_size,
            strokecolor = :black,
            strokewidth = 0.5,
        )
    end

    # ── Display helpers ──────────────────────────────────────────────────

    # Convert stored relative coords to display axis coordinates.
    # image!(ax, M) with implicit extents places pixel centers at x ∈ 1..w, y ∈ 1..h.
    # With flipped image (no yreversed): axis y increases upward, so original row r
    # appears at y = h + 1 - r. For relative coords: axis_y = (1 - p.y) * h + 1.
    rel_to_ax(p::CountPoint) =
        Point2f(p.x * Float64(w) + 0.5, (1.0 - p.y) * Float64(h) + 0.5)

    function refresh_display!()
        counts = count_by_tag(sess)
        msize = sess.marker_size
        for (i, tag) in enumerate(sess.tags)
            tag_pts_obs[i][] = [rel_to_ax(p) for p in sess.points if p.tag == tag.name]
            count_obs[i][] = counts[tag.name]
            scatter_plots[i].markersize[] = msize
        end
        total_obs[] = total_count(sess)
        active_tag_obs[] = sess.active_tag
    end

    # Rebuild scatter data for one tag only (used during drag for performance).
    function refresh_tag!(tag_name::String)
        i = findfirst(t -> t.name == tag_name, sess.tags)
        isnothing(i) && return
        tag_pts_obs[i][] = [rel_to_ax(p) for p in sess.points if p.tag == tag_name]
    end

    refresh_display!()

    # ── Control panel layout ─────────────────────────────────────────────
    # Wrap in a GridLayout with outer padding so content doesn't hug the edges.
    panel_grid = GridLayout(panel; padding = (8, 8, 8, 8))
    row = 1

    # Hint labels styled as small secondary text to visually separate
    # instructions from interactive controls.
    hint_color = RGBf(0.45, 0.45, 0.45)
    Label(
        panel_grid[row, 1],
        "Left-click: add  |  Right-click: delete  |  Left-drag: move";
        halign = :left,
        tellwidth = false,
        fontsize = 11,
        color = hint_color,
    )
    row += 1
    Label(
        panel_grid[row, 1],
        "Scroll: zoom in/out  |  R: reset view";
        halign = :left,
        tellwidth = false,
        fontsize = 11,
        color = hint_color,
    )
    row += 1

    # ── Zoom buttons ─────────────────────────────────────────────────────
    # Shared style for all non-tag buttons: slightly off-white background with
    # a thin black border so they stand out from the panel background.
    btn_style =
        (buttoncolor = RGBf(0.86, 0.86, 0.86), strokecolor = :black, strokewidth = 1)

    zoom_btn_grid = GridLayout(panel_grid[row, 1]; tellwidth = true)
    colgap!(zoom_btn_grid, 5)
    zoom_out_btn = Button(
        zoom_btn_grid[1, 1];
        btn_style...,
        label = "-  Zoom Out",
        tellwidth = true,
        height = 32,
    )
    reset_view_btn = Button(
        zoom_btn_grid[1, 2];
        btn_style...,
        label = "Reset View",
        tellwidth = true,
        height = 32,
    )
    zoom_in_btn = Button(
        zoom_btn_grid[1, 3];
        btn_style...,
        label = "Zoom In  +",
        tellwidth = true,
        height = 32,
    )
    row += 1
    row_after_zoom = row - 1  # section boundary: zoom controls → tag selector

    on(zoom_in_btn.clicks) do _
        fl = ax.finallimits[]
        x0, y0 = fl.origin
        dx, dy = fl.widths
        ax.limits[] = _zoom_in_limits(x0, x0 + dx, y0, y0 + dy)
    end

    on(zoom_out_btn.clicks) do _
        fl = ax.finallimits[]
        x0, y0 = fl.origin
        dx, dy = fl.widths
        ax.limits[] = _zoom_out_limits(x0, x0 + dx, y0, y0 + dy, w, h)
    end

    on(reset_view_btn.clicks) do _
        ax.limits[] = (0.5, Float64(w) + 0.5, 0.5, Float64(h) + 0.5)
    end

    # R key: reset view (explicit handler — the built-in limitreset interaction
    # is unreliable across Makie versions and focus states).
    on(events(fig).keyboardbutton) do event
        if event.action in (Keyboard.press, Keyboard.repeat) && event.key == Keyboard.r
            ax.limits[] = (0.5, Float64(w) + 0.5, 0.5, Float64(h) + 0.5)
        end
    end

    # Active tag indicator
    active_txt = @lift("Active tag: $($active_tag_obs)")
    Label(panel_grid[row, 1], active_txt; halign = :left, tellwidth = false)
    row += 1

    # ── Tag selector buttons ─────────────────────────────────────────────
    Label(
        panel_grid[row, 1],
        "Select tag:";
        halign = :left,
        tellwidth = false,
        font = :bold,
    )
    row += 1

    for tag in sess.tags
        btn = Button(
            panel_grid[row, 1];
            label = tag.name,
            buttoncolor = tag.color,
            labelcolor = :white,
            tellwidth = true,
            height = 32,
        )
        on(btn.clicks) do _
            set_active_tag!(sess, tag.name)
            active_tag_obs[] = sess.active_tag
            status_obs[] = "Active tag: $(sess.active_tag)"
        end
        row += 1
    end
    row_after_tags = row - 1  # section boundary: tag selector → marker size

    # ── Marker size slider ───────────────────────────────────────────────
    Label(
        panel_grid[row, 1],
        "Marker size:";
        halign = :left,
        tellwidth = false,
        font = :bold,
    )
    row += 1
    sl_range = 5:1:40
    start_val = clamp(round(Int, sess.marker_size), first(sl_range), last(sl_range))
    size_slider = Slider(
        panel_grid[row, 1];
        range = sl_range,
        startvalue = start_val,
        tellwidth = true,
    )
    row += 1
    row_after_slider = row - 1  # section boundary: marker size → counts
    on(size_slider.value) do v
        set_marker_size!(sess, Float64(v))
        for sp in scatter_plots
            sp.markersize[] = sess.marker_size
        end
    end

    # ── Count display ────────────────────────────────────────────────────
    Label(panel_grid[row, 1], "Counts:"; halign = :left, tellwidth = false, font = :bold)
    row += 1

    total_lbl = @lift("Total: $($total_obs)")
    Label(panel_grid[row, 1], total_lbl; halign = :left, tellwidth = false)
    row += 1

    for (i, tag) in enumerate(sess.tags)
        tag_lbl = @lift("$(tag.name): $($(count_obs[i]))")
        Label(
            panel_grid[row, 1],
            tag_lbl;
            halign = :left,
            color = tag.color,
            tellwidth = false,
        )
        row += 1
    end
    row_after_counts = row - 1  # section boundary: counts → action buttons

    # ── Action buttons ───────────────────────────────────────────────────
    save_btn = Button(
        panel_grid[row, 1];
        btn_style...,
        label = "Save session",
        tellwidth = true,
        height = 36,
    )
    row += 1
    load_btn = Button(
        panel_grid[row, 1];
        btn_style...,
        label = "Load session",
        tellwidth = true,
        height = 36,
    )
    row += 1
    export_btn = Button(
        panel_grid[row, 1];
        btn_style...,
        label = "Export CSV",
        tellwidth = true,
        height = 36,
    )
    row += 1

    Label(panel_grid[row, 1], status_obs; halign = :left, tellwidth = false)

    # ── Section spacing ──────────────────────────────────────────────────
    # Add visual gaps at major section boundaries (replaces the empty spacer Labels).
    rowgap!(panel_grid, row_after_zoom, 14)
    rowgap!(panel_grid, row_after_tags, 14)
    rowgap!(panel_grid, row_after_slider, 14)
    rowgap!(panel_grid, row_after_counts, 14)

    # ── File path helpers ────────────────────────────────────────────────
    function toml_path()
        dir = dirname(abspath(sess.image_path))
        base = splitext(basename(sess.image_path))[1]
        return joinpath(dir, base * "_session.toml")
    end
    function csv_path()
        dir = dirname(abspath(sess.image_path))
        base = splitext(basename(sess.image_path))[1]
        return joinpath(dir, base * "_counts.csv")
    end

    # ── Button callbacks ─────────────────────────────────────────────────
    on(save_btn.clicks) do _
        try
            p = toml_path()
            save_session(sess, p)
            status_obs[] = "Saved: $(basename(p))"
        catch e
            status_obs[] = "Save error: $e"
        end
    end

    on(load_btn.clicks) do _
        p = toml_path()
        if isfile(p)
            try
                loaded = load_session(p)
                if length(loaded.tags) != length(sess.tags)
                    status_obs[] =
                        "Cannot load: tag count differs " *
                        "(session has $(length(loaded.tags)), current has $(length(sess.tags)))"
                else
                    sess.points = loaded.points
                    sess.next_id = loaded.next_id
                    sess.active_tag = loaded.active_tag
                    sess.marker_size = loaded.marker_size
                    sess.tags = loaded.tags
                    size_slider.value[] =
                        clamp(round(Int, sess.marker_size), first(sl_range), last(sl_range))
                    refresh_display!()
                    status_obs[] = "Loaded: $(basename(p))"
                end
            catch e
                status_obs[] = "Load error: $e"
            end
        else
            status_obs[] = "Not found: $(basename(p))"
        end
    end

    on(export_btn.clicks) do _
        try
            p = csv_path()
            export_csv(sess, p)
            status_obs[] = "Exported: $(basename(p))"
        catch e
            status_obs[] = "Export error: $e"
        end
    end

    # ── Mouse interaction ────────────────────────────────────────────────
    dragging = Ref(false)
    drag_id = Ref{Union{Int,Nothing}}(nothing)
    drag_tag_name = Ref{Union{String,Nothing}}(nothing)

    on(events(fig).mousebutton; priority = 2) do event
        # Only act on clicks that land inside the image axis.
        # is_mouseinside checks ax's viewport in screen pixels.
        if !is_mouseinside(ax)
            return Consume(false)
        end

        # mouseposition(ax) returns axis data-space coords.
        # With flipped image (no yreversed): axis y increases upward,
        # so pixel row = (h+1) - axis_y.
        pos = mouseposition(ax)
        x_px = Float64(pos[1])
        y_px = Float64(h) + 1.0 - Float64(pos[2])

        if event.button == Mouse.left

            if event.action == Mouse.press
                nearest = find_nearest_point(sess, x_px, y_px; threshold = 30.0)
                if !isnothing(nearest)
                    # Start dragging the nearest point
                    dragging[] = true
                    drag_id[] = nearest.id
                    drag_tag_name[] = nearest.tag
                else
                    # Add a new point at the click location
                    add_point!(sess, x_px, y_px)
                    refresh_display!()
                end
                return Consume(true)

            elseif event.action == Mouse.release && dragging[]
                dragging[] = false
                drag_id[] = nothing
                drag_tag_name[] = nothing
                refresh_display!()
                return Consume(true)
            end

        elseif event.button == Mouse.right && event.action == Mouse.press
            nearest = find_nearest_point(sess, x_px, y_px; threshold = 50.0)
            if !isnothing(nearest)
                delete_point!(sess, nearest.id)
                refresh_display!()
                return Consume(true)
            end
        end

        return Consume(false)
    end

    # Mouse move → update the dragged point's position.
    # Only the affected tag's scatter is rebuilt (performance).
    on(events(fig).mouseposition; priority = 2) do _
        if !dragging[] || isnothing(drag_id[])
            return
        end
        pos = mouseposition(ax)
        x_px = Float64(pos[1])
        y_px = Float64(h) + 1.0 - Float64(pos[2])
        move_point!(sess, drag_id[], x_px, y_px)
        if !isnothing(drag_tag_name[])
            refresh_tag!(drag_tag_name[])
        end
    end

    display(fig)
    return fig, sess
end

end # module GLMakieExt
