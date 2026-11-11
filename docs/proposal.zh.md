# MoonPDF 项目申报书

## 基本信息

- **项目名称**：MoonPDF：MoonBit 原生 PDF 页面渲染引擎
- **参赛者**：Yjh4899 ｜ **联系方式**：<待填写>
- **GitHub**：https://github.com/Yjh4899/moonpdf
- **mooncakes**：https://mooncakes.io/docs/Yjh4899/moonpdf
- **方向**：文档处理引擎 / 图形与渲染基础设施
- **类型**：原创实现（参考 PDF 规范与成熟渲染器的公开行为，不复制源码）

## 项目简介

MoonBit 已经能“读写 PDF”：`pdflite`/`mbtpdf` 负责对象解析与改写，`pagelayout` 负责生成，官方 office-viewer 的 PDF 预览直接嵌入 PDF.js。缺的是“把某一页变成像素”的最后一公里——任何需要缩略图、OCR 前置或视觉回归的 MoonBit 程序，目前都得带一个 JS 虚拟机或调用外部二进制。

MoonPDF 用纯 MoonBit 完成 **对象解析 → 内容流解释 → 图形状态与路径 → 扫描线光栅化 → PNG**，无 FFI、无浏览器，可编译到 native / wasm，既可作为库调用，也提供 CLI。

## 三个使用场景

1. **文档服务**：后端收到上传的 PDF，返回首屏缩略图给审核队列；现在需要 Node/PDF.js 或系统 `pdftoppm`，接入后是一次库调用。
2. **AI/Agent 文档处理**：多模态模型与 OCR 需要页面图像而不是 PDF 字节；MoonPDF 在服务、CLI 或 wasm 中确定性地输出 PNG。
3. **桌面/IDE 预览与 CI 视觉回归**：文档工具内嵌页面预览；生成器在 CI 中渲染自己的输出并比较页面哈希，及时发现排版回归。

## 核心功能与边界

**本期已完成**：经典 xref、间接对象、页面树与资源继承；`q/Q/cm`、路径构造、填充/描边、RGB/灰度/CMYK、线宽与线帽；文本状态与 `Td/TD/Tm/T*/Tj/TJ/'/"`、回退字形；2× 超采样扫描线光栅化；PNG 输出；CLI、单元测试、fixture 与 CI。

**后续**：FlateDecode、xref/object stream、图片 XObject、嵌入 TrueType/CFF 轮廓、裁剪与透明组、SVG 输出、wasm 演示。

**不做**：PDF 编辑/表单/签名/解密、JS 执行、OCR 与语义版面分析、与某一渲染器的逐像素完全一致。

## 技术路线

分层实现，每层可独立测试：字节游标与词法 → 对象解析 → xref 与页面树 → 内容流操作符 → 图形状态机 → 路径展平 → 扫描线填充/描边 → PNG（core zlib + CRC32）。解析错误显式抛出，不做静默修复；不支持的文档结构给出明确错误，不输出“看起来对”的图。字体先用回退字形锁定版面与文本状态，M2 再替换为 TrueType 轮廓，解释器接口不变。

## 风险与应对

- **字体保真度**：先回退字形，后上轮廓字体与字形缓存。
- **PDF 特性面宽**：用兼容性矩阵和“声明的子集”控制范围，语料驱动验收。
- **光栅化正确性**：单元测试 + 固定 fixture + 页面哈希，后续加 MuPDF 差分/SSIM。
- **性能**：超采样参数可调，后续 tile 渲染与自适应曲线细分。

## 参考与许可

参考 PDF 32000-1:2008 规范及 MuPDF、PDFium、Poppler 的公开行为，不复制其源码；与 `pdflite`、`moonbitlang/office` 互补，不 vendor 其代码。项目采用 Apache-2.0。

## 当前进度

18 次有意义提交；13 个单元测试通过；CI 覆盖格式化、检查、测试与渲染；3 个 fixture 可端到端渲染；已发布 `Yjh4899/moonpdf@0.1.0`。详细范围与路线见 `docs/scope.md`、`docs/roadmap.md`。
