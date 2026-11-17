///|
/// Integration-test helpers. This package is not part of the published library;
/// it exists so the repository can exercise end-to-end fixtures on every test
/// run, including the incremental-update and xref-stream cases.

///|
pub fn fixture_bytes(path : String) -> Bytes {
  @fs.read_file_to_bytes(path) catch {
    _ => Bytes::make(0, 0)
  }
}

///|
pub fn rasterize(data : Bytes, scale : Double) -> @render.RenderedPage? {
  let document = @pdf.parse_document(data) catch { _ => return None }
  let page = match document.page(0) {
    Some(page) => page
    None => return None
  }
  Some(
    @render.render_page(page, @render.RenderOptions::with_scale(scale)) catch {
      _ => return None
    },
  )
}
