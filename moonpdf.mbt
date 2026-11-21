///|
/// Public facade for the MoonPDF library.
///
/// The parser and the renderer live in separate packages so that document
/// inspection tools can use the object model without pulling in the rasterizer.

///|
pub suberror MoonPdfError {
  MoonPdfError(String)
}

///|
/// An opened document. Keeping the parsed document alive lets callers render
/// many pages without reparsing the xref chain, page tree and fonts.
pub struct MoonPdfDocument {
  document : @pdf.PdfDocument
}

///|
pub fn open(data : Bytes) -> MoonPdfDocument raise MoonPdfError {
  let document = @pdf.parse_document(data) catch {
    @pdf.PdfError(msg) => raise MoonPdfError(msg)
  }
  { document, }
}

///|
pub fn MoonPdfDocument::page_count(self : MoonPdfDocument) -> Int32 {
  self.document.page_count()
}

///|
pub fn MoonPdfDocument::render_png(
  self : MoonPdfDocument,
  page_index : Int32,
  scale : Double,
) -> Bytes raise MoonPdfError {
  let page = match self.document.page(page_index) {
    Some(p) => p
    None => raise MoonPdfError("page index out of range")
  }
  let options = @render.RenderOptions::with_scale(scale)
  let raster = @render.render_page(page, options) catch {
    @render.RenderError(msg) => raise MoonPdfError(msg)
  }
  @render.encode_png(raster)
}

///|
pub fn MoonPdfDocument::render_svg(
  self : MoonPdfDocument,
  page_index : Int32,
  scale : Double,
) -> Bytes raise MoonPdfError {
  let page = match self.document.page(page_index) {
    Some(p) => p
    None => raise MoonPdfError("page index out of range")
  }
  let options = @render.RenderOptions::with_scale(scale)
  let vector = @render.encode_svg_vector(page, options) catch {
    @render.RenderError(msg) => raise MoonPdfError(msg)
  }
  match vector {
    Some(svg) => svg
    None => {
      let raster = @render.render_page(page, options) catch {
        @render.RenderError(msg) => raise MoonPdfError(msg)
      }
      @render.encode_svg(raster)
    }
  }
}

///|
pub fn MoonPdfDocument::render_pages_png(
  self : MoonPdfDocument,
  page_indices : Array[Int32],
  scale : Double,
) -> Array[Bytes] raise MoonPdfError {
  let options = @render.RenderOptions::with_scale(scale)
  let out : Array[Bytes] = Array(capacity=page_indices.length())
  for index in page_indices {
    let page = match self.document.page(index) {
      Some(p) => p
      None => raise MoonPdfError("page index out of range")
    }
    let raster = @render.render_page(page, options) catch {
      @render.RenderError(msg) => raise MoonPdfError(msg)
    }
    out.push(@render.encode_png(raster))
  }
  out
}

///|
pub fn MoonPdfDocument::render_pages_svg(
  self : MoonPdfDocument,
  page_indices : Array[Int32],
  scale : Double,
) -> Array[Bytes] raise MoonPdfError {
  let options = @render.RenderOptions::with_scale(scale)
  let out : Array[Bytes] = Array(capacity=page_indices.length())
  for index in page_indices {
    let page = match self.document.page(index) {
      Some(p) => p
      None => raise MoonPdfError("page index out of range")
    }
    let vector = @render.encode_svg_vector(page, options) catch {
      @render.RenderError(msg) => raise MoonPdfError(msg)
    }
    match vector {
      Some(svg) => out.push(svg)
      None => {
        let raster = @render.render_page(page, options) catch {
          @render.RenderError(msg) => raise MoonPdfError(msg)
        }
        out.push(@render.encode_svg(raster))
      }
    }
  }
  out
}

///|
pub fn page_count(data : Bytes) -> Int32 raise MoonPdfError {
  let document = @pdf.parse_document(data) catch {
    @pdf.PdfError(msg) => raise MoonPdfError(msg)
  }
  document.page_count()
}

///|
pub fn render_page_png(
  data : Bytes,
  page_index : Int32,
  scale : Double,
) -> Bytes raise MoonPdfError {
  let document = @pdf.parse_document(data) catch {
    @pdf.PdfError(msg) => raise MoonPdfError(msg)
  }
  let page = match document.page(page_index) {
    Some(p) => p
    None => raise MoonPdfError("page index out of range")
  }
  let options = @render.RenderOptions::with_scale(scale)
  let raster = @render.render_page(page, options) catch {
    @render.RenderError(msg) => raise MoonPdfError(msg)
  }
  @render.encode_png(raster)
}

///|
/// Render several pages, parsing the document only once.
pub fn render_pages_png(
  data : Bytes,
  page_indices : Array[Int32],
  scale : Double,
) -> Array[Bytes] raise MoonPdfError {
  let document = @pdf.parse_document(data) catch {
    @pdf.PdfError(msg) => raise MoonPdfError(msg)
  }
  let options = @render.RenderOptions::with_scale(scale)
  let out : Array[Bytes] = Array(capacity=page_indices.length())
  for index in page_indices {
    let page = match document.page(index) {
      Some(p) => p
      None => raise MoonPdfError("page index out of range")
    }
    let raster = @render.render_page(page, options) catch {
      @render.RenderError(msg) => raise MoonPdfError(msg)
    }
    out.push(@render.encode_png(raster))
  }
  out
}

///|
/// Render several pages as SVG containers.
pub fn render_pages_svg(
  data : Bytes,
  page_indices : Array[Int32],
  scale : Double,
) -> Array[Bytes] raise MoonPdfError {
  let document = @pdf.parse_document(data) catch {
    @pdf.PdfError(msg) => raise MoonPdfError(msg)
  }
  let options = @render.RenderOptions::with_scale(scale)
  let out : Array[Bytes] = Array(capacity=page_indices.length())
  for index in page_indices {
    let page = match document.page(index) {
      Some(p) => p
      None => raise MoonPdfError("page index out of range")
    }
    let vector = @render.encode_svg_vector(page, options) catch {
      @render.RenderError(msg) => raise MoonPdfError(msg)
    }
    match vector {
      Some(svg) => out.push(svg)
      None => {
        let raster = @render.render_page(page, options) catch {
          @render.RenderError(msg) => raise MoonPdfError(msg)
        }
        out.push(@render.encode_svg(raster))
      }
    }
  }
  out
}

///|
/// Render one page as a self-contained SVG with an embedded PNG image.
pub fn render_page_svg(
  data : Bytes,
  page_index : Int32,
  scale : Double,
) -> Bytes raise MoonPdfError {
  let document = @pdf.parse_document(data) catch {
    @pdf.PdfError(msg) => raise MoonPdfError(msg)
  }
  let page = match document.page(page_index) {
    Some(p) => p
    None => raise MoonPdfError("page index out of range")
  }
  let options = @render.RenderOptions::with_scale(scale)
  let vector = @render.encode_svg_vector(page, options) catch {
    @render.RenderError(msg) => raise MoonPdfError(msg)
  }
  match vector {
    Some(svg) => svg
    None => {
      let raster = @render.render_page(page, options) catch {
        @render.RenderError(msg) => raise MoonPdfError(msg)
      }
      @render.encode_svg(raster)
    }
  }
}
