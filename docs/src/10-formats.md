# Supported Image Formats

ImageTally uses [FileIO.jl](https://github.com/JuliaIO/FileIO.jl) and
[ImageIO.jl](https://github.com/JuliaIO/ImageIO.jl) for image loading,
supporting a wide range of scientific and photographic image formats.

## Tested formats

The following formats are part of the CI test suite and officially supported:

### JPEG (`.jpg`, `.jpeg`)

The most common format for field photography and camera output.
JPEG uses lossy compression, which is fine for counting but means
pixel values are slightly altered from the original. Recommended
for photographs from digital cameras.

```julia
fig, sess = launch_counter("field_photo.jpg")
```

### PNG (`.png`)

Lossless compression — pixel values are preserved exactly. Recommended
when image quality must be maintained precisely, such as processed
microscopy images or images that will be analyzed further.

```julia
fig, sess = launch_counter("microscopy.png")
```

### TIFF (`.tif`, `.tiff`)

The standard format for scientific imaging. ImageTally supports:

- **8-bit RGB** — standard color images from microscopes and cameras
- **8-bit Grayscale** — single-channel images common in brightfield microscopy
- **16-bit Grayscale** — high dynamic range images from scientific cameras.
  These load correctly but are displayed with automatic contrast adjustment
  by GLMakie.

```julia
fig, sess = launch_counter("microscopy_16bit.tif")
```

### BMP (`.bmp`)

Uncompressed bitmap format. Supported but produces large file sizes.
Less common in modern scientific workflows.

## Large images

ImageTally has been tested with images up to 3456×5184 pixels
(approximately 18 megapixels) with good interactive performance
on a desktop GPU. Images larger than approximately 8000 pixels
on either dimension may cause slower rendering depending on
your hardware.

## Camera RAW formats

Camera RAW formats (`.rw2`, `.cr2`, `.nef`, `.arw`, and others)
are **not directly supported**. These proprietary formats require
specialized decoders not currently available in the Julia ecosystem.

Convert RAW files to TIFF or JPEG before using ImageTally:

**darktable** (free, recommended):

```bash
darktable-cli image.rw2 output.tif
```

**RawTherapee** (free):
Use the batch processing feature to convert multiple files.

**dcraw** (command line):

```bash
dcraw -T image.rw2    # converts to TIFF
```

**Adobe Lightroom / Capture One** (paid):
Export to TIFF or JPEG from the export dialog.

## Programmatic loading

You can load images manually and inspect their properties before
creating a session:

```julia
using FileIO, ImageIO
using ImageTally

# Load and inspect
img = FileIO.load("image.tif")
println(typeof(img))     # e.g. Matrix{RGB{N0f8}}
println(size(img))       # (height, width)

# Note: size(img) returns (height, width) in Julia
h, w = size(img)

# Create session with correct dimensions
sess = new_session("image.tif", w, h)
```

## Multi-channel and multi-slice images

Fluorescence microscopy images sometimes contain multiple channels
or Z-slices stacked in a single TIFF file. These load as 3D or 4D
arrays rather than 2D arrays and are **not currently supported**.
Export individual channels or maximum intensity projections as
separate 2D TIFF files before using ImageTally.
