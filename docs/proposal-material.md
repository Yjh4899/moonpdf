# 申报书素材：MoonPDF 的技术取舍

这份材料给申报书使用，不替代 `docs/申报书.md`。内容按赛事六条验收标准和四个技术取舍组织，所有数字都能在仓库里找到出处。

## 一句话定位

MoonPDF 用纯 MoonBit 补齐 MoonBit 生态缺少的“PDF 页面 → 像素”一层：不依赖 PDF.js、JavaScript VM、C 库或浏览器，输出 PNG / 矢量 SVG，可作为缩略图、OCR 前置、文档预览和视觉回归的基础设施。

## 六条验收标准 → 仓库证据

| 验收条 | 仓库证据 |
| --- | --- |
| MoonBit 为主 | `pdf/`、`render/`、`cmd/` 全部 MoonBit；约 98.7k 行、244 个 `.mbt`、2.89 MB 源码 |
| 仓库公开、提交连续 | GitHub `Yjh4899/moonpdf`；227 次提交，连续开发；issue/PR/更新记录可见 |
| 能够运行 | `README.md` 三条命令可跑；`examples/README.md`、`demo/index.html`；77 个测试；CI 全绿 |
| 本期工作有效 | xref/对象流、增量更新、字体、图像、透明度、clipping、shading、pattern、annotation、SVG 等均为本期实现；见 `docs/scope.md` |
| 开源合规 | Apache-2.0；PDF 规范引用；内置 OpenSans 子集为 SIL OFL 1.1，`fixtures/fonts/OFL.txt` |
| AI 可解释 | 56 条 ADR（`docs/decisions.md`）、架构/兼容性/验收文档；关键取舍见下 |

## 取舍一：手写 CFF/Type 2，而不是移植 FreeType

**选择**：手写 CFF INDEX/DICT、charset、FDArray/FDSelect、Type 2 charstring 解释器。

**原因**：

- MoonBit 生态没有可直接复用的 CFF 轮廓引擎；
- 引入 C 库会破坏 wasm/native 的纯 MoonBit 构建；
- PDF 子集字体需要的只是轮廓，不需要完整排版引擎。

**代价**：

- 复杂子集、hint、seac 等边界要自己补；
- 真实表单仍有字体面差异（IRS 约 82%）。

**为什么仍然合理**：它让“嵌入 CFF 的 PDF 可渲染”成为 MoonBit 内部能力，而不是外部依赖；剩余差异有明确的差分记录，不是未知崩溃。

## 取舍二：透明度组/soft mask 用覆盖平面，而不是完整 PDF 透明模型

**选择**：

- 隔离透明组用白/黑 backdrop 差分提取；
- ExtGState `/SMask` 用页面级 coverage plane；
- blend mode 用 PDF/W3C 公式，非分离模式实现 `SetLum`/`SetSat`。

**原因**：完整 PDF 透明模型（knockout、group alpha、色彩空间混合）实现量过大；页面级覆盖平面能覆盖真实文档的绝大多数场景，且保持确定性。

**代价**：极端 blend/soft-mask 组合与参考渲染器仍有像素差；blendmode 样例约 87%。

**验证**：`fixtures/soft-mask*.pdf`、`transparency-group.pdf`、`blend.pdf` 为回归；真实 PDF.js 样例走差分。

## 取舍三：标准 14 字体用内置 OpenSans fallback，而不是位图

**选择**：内置 67 KB OpenSans 子集（OFL，zlib+Base64），标准 14 / 无嵌入轮廓字体优先用矢量 fallback。

**原因**：

- 3×5 位图在 20–24pt 下会变成明显黑块；
- 系统字体不可移植，wasm 也没有文件系统；
- OpenSans 可嵌入、许可证清晰、跨平台确定。

**代价**：

- 与参考渲染器的 Times/Helvetica 字形不同，fixture 通过数从 36 降到 34；
- 这是有意的“真实文档可用性优先”取舍，已写入 ADR-054。

**收益**：arXiv 侧边印章、ResNet 图表标签从块状字变为矢量字；attention 真实 PDF 达到 90.2%。

## 取舍四：差分 corpus + fuzz，而不是只写单元测试

**选择**：

- 39 个提交 fixture；
- 13 个公共真实 PDF，与 PyMuPDF 做 MAE / 像素接近度差分；
- 120 个 malformed case fuzz；
- 干净 clone、CI、CLI smoke、验收审计。

**原因**：PDF 渲染的 bug 往往只在真实内容流/字体/透明度组合里出现；单元测试无法覆盖。

**代价**：真实 corpus 只有 5/13 达到 90%，剩余 8 个已记录差距；这比“只报通过”更可信，也明确告诉评审边界。

**结果**：所有真实 PDF 可渲染、0 crash、0 timeout；fuzz 0 crash / 0 timeout。

## 验证数字（0.44.0 候选）

- 77 个单元/集成测试；
- 39 个 fixture：39 渲染，34 容差内，0 fail；
- 13 个真实 PDF：13 渲染，5 容差内，0 crash / 0 timeout；
- 120 fuzz：0 crash / 0 timeout；
- `moon check --deny-warn`、clean clone、CLI smoke 通过。

## 建议在申报书里强调的三点

1. **生态缺口明确**：MoonBit 能解析/生成 PDF，但缺“页面 → 像素”的最后一公里；MoonPDF 补的是基础设施，不是又一个 PDF 读写库。
2. **工程闭环完整**：规范覆盖 → 实现 → 差分 → fuzz → CI → 发布 → 验收审计，链条可复现。
3. **边界诚实**：真实 corpus 5/13 通过、8 个差距、字体 hinting 未完全复现；这些写在 `docs/acceptance.md`，而不是隐藏。

## 可直接引用的文件

- `docs/acceptance.md` — 验收审计与已知差距
- `docs/decisions.md` — 56 条 ADR
- `docs/corpus-report-real.md` — 真实 PDF 差分
- `docs/corpus-report.md` — fixture 差分
- `docs/fuzz-report.md` — fuzz 结果
- `demo/index.html` — 可视化展示
- `docs/release-0.44.0.md` — 版本说明
