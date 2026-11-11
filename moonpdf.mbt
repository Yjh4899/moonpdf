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
    _ => raise MoonPdfError("failed to render page")
  }
  @render.encode_png(raster)
}
