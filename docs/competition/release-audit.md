# 发布工程审计

核验日期：2026-11-21。此文件记录本地工程门槛；公开 CI、Release、精确版本与消费者结果以最终本地交付记录及对应公开链接为准，不将预检当作发布成功。

## 代码与验证

生产代码计数与输入摘要见 [验收说明](../validation.md)。核心共 2,027 物理行，8 个根目录生产 `.mbt` 文件；排除所有测试、示例、生成接口、配置及文档。`moon info`、`moon fmt --check`、`moon check --target all --deny-warn --warn-list=-78` 通过，三本地目标各 35 项测试及构建通过。规则 78 为保留公开 Result API 的单项豁免。Windows 缺少 C 编译器，native 必须由远端实际 CI 核验。

## 有效提交审计

以下 20 个工程切片保留各自可审查的结果，验证包括相应回归以及最终全量测试。以最终内容审查，两个字符串预算后续修正归并到原始切片，不重复计数。最后的审计/日期文档提交不计工程数量。

| SHA | 工程目的与验证 | 涉及文件 |
|---|---|---|
| `d53acafe0f20023a2b5b56d55708ac5156ef8b6a` | 建立文件帧、实体、索引、几何和受限解码完整核心；公开最小示例与原始测试 | .githooks/README.md, .githooks/pre-commit, .github/workflows/ci.yml, .github/workflows/copilot-setup-steps.yml, .gitignore, AGENTS.md 等共 25 项 |
| `97c714d8b41339e211b374f764e4bfdad8882572` | 拒绝 field-zero、过长及溢出 varint；wire 错误回归 | proto.mbt, proto_wbtest.mbt |
| `2124ac55719854b21345bf9063876c44cbebcb75` | 修复 Int64 全范围 zigzag 半移位；极值回归 | entities.mbt, proto_wbtest.mbt |
| `f4d15e4068c744f7d168018d07209cae185d96f0` | BlobHeader datasize 缩窄前校验；超范围和截断回归 | framing.mbt, framing_wbtest.mbt |
| `f576ce78882922c89e602fe7a480a49985f3046a` | UTF-8、空字符串表条目和跨字段累计预算；含两个后续修正的最终结果 | entities.mbt, entities_wbtest.mbt |
| `64f9d7b125f52216190d030333ed52171c3d7aa5` | 拒绝无效 granularity 及转换溢出；精确错误回归 | entities.mbt, entities_wbtest.mbt |
| `7a429400bca0a661b2f5300b723473c0d3f01a07` | DenseNodes 标签必须完整结束；缺失终止符回归 | entities.mbt, entities_wbtest.mbt |
| `2974be5b1a77ca2906cb249ca8d1efd07b04a5d2` | 坐标缩放/偏移溢出和经纬度范围校验；坐标回归 | coordinates.mbt, coordinates_wbtest.mbt, entities.mbt |
| `786636172dc906a996967c8c4cd535d9d4ed3c82` | 节点、Way、Relation 差分累加溢出校验；引用/成员回归 | entities.mbt, entities_wbtest.mbt |
| `eae2ccbb9a7e96319e0ae94cb6176172f19a0751` | 公开可配置资源上限及其验证；非法配置回归 | entities.mbt, framing.mbt, framing_wbtest.mbt, moonosm.mbt |
| `a0135f87e0bb7b1db4a9b320d8c531eee4cc1089` | 文件解码状态机要求单个初始 Header；顺序/重复 Header 回归 | framing.mbt, moonosm_test.mbt |
| `e54b5ec65eb1b314afca9f61e4a08fae84ee92ce` | 结构化 JSONL 实体导出及文件入口；转义/实体输出测试 | README.md, examples/decode_file/main.mbt, jsonl.mbt, moonosm.mbt, moonosm_test.mbt, query.mbt |
| `a46b50e0b54a00e069cf8a929cbc364d591e7610` | 无效范围下筛选统计与结果一致；统计不变量回归 | moonosm_test.mbt, query.mbt |
| `ea5215b749655950b59b56630ab318c47dc23e61` | 范围内 GeoJSON 和分段裁剪输出；JSON 分隔符和几何回归 | README.md, docs/competition/duplicate-check.md, geometry.mbt, moonosm_test.mbt |
| `3d0ee5b2b9e2727331db923a9d7c740fcedab91b` | 构造下一块实体之前传递剩余预算；跨块/普通/DenseNodes 回归 | entities.mbt, entities_wbtest.mbt, framing.mbt, moonosm_test.mbt |
| `06e3a35082b6193ea13a42d899b803ccbc1ccac1` | 普通 Node ID 按 sint64 而非 int64 解码；正负 Node 和 Way 对照 | entities.mbt, entities_wbtest.mbt, examples/decode/main.mbt, moonosm_test.mbt |
| `f0f0b32f826d916ae1f87aef0a63fc65f2c89043` | 跳过未知长度字段不复制 payload；边界及后续字段回归 | proto.mbt, proto_wbtest.mbt |
| `bc8063522842c2bef222ecc6a6595226119f203e` | 公开错误消息保留偏移、压缩与预算；诊断 API 回归 | README.md, diagnostics_test.mbt, moonosm.mbt |
| `d07ac0ce5304ab11e8394c308c94643e339515b8` | 文件标签/范围提取与独立节点索引；三真实任务及公开例子运行 | .github/workflows/ci.yml, README.md, examples/extract/main.mbt, examples/extract/moon.pkg, examples/geojson/main.mbt, examples/geojson/moon.pkg |
| `c7544355c74ca9a7a3a6f833c92107815235392d` | 可复现外部解析器差分与三场景独立验收脚本；真实样本运行 | docs/competition/duplicate-check.md, docs/validation.md, scripts/compare_reference.cjs, scripts/verify_extracts.py |

不单独计数：

- `786f36d`：同一字符串预算修复的跟进，合并计入 f576ce7，不单独计数。
- `3a17b85`：同一字符串预算修复的跟进，合并计入 f576ce7，不单独计数。
- `c5eff9c`：仅日期改动，不计工程提交。

本次审计前原始提交 23 个，保守有效工程提交 20 个；此审计文档本身不增加有效数。实际作者关联在推送后通过 GitHub commit API 核验。
