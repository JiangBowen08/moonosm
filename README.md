# MoonOSM

MoonOSM 是 MoonBit 编写的 OpenStreetMap Protocolbuffer Binary Format（OSM PBF）读取库。它将带边界检查的 PBF 文件帧和 Blob 解码为节点、Way、Relation 与标签，提供类型/标签/范围筛选，并可将节点和 Way 导出为 JSONL 或 GeoJSON。

## 环境与安装

项目 manifest 版本为 `0.1.0`，使用 MoonBit `0.1.20261119` 或更新版本。zlib 解码依赖工具链中的实验性 `moonbitlang/core/compress/zlib` API。源码检出后可在其他 MoonBit 模块中依赖本地包；公开版本发布后，模块坐标为 `JiangBowen08/moonosm@0.1.0`。

## 能力与边界

- 解码 PBF 文件帧、BlobHeader、OSMHeader 和 PrimitiveBlock；接受 raw 与 zlib Blob。
- 解码普通节点、DenseNodes、Way、Relation、坐标、标签、Way 引用与 Relation 成员。
- 对 header、Blob、解压后字节、字符串及实体数量设置可配置上限；检查截断、非法 varint、无效 UTF-8、互斥 Blob 字段冲突、zlib 校验和及声明长度。
- 拒绝不支持的 required feature；对 LZMA、bzip2、LZ4、Zstandard 压缩返回明确错误。
- 依据实体类型、精确标签、节点范围或 Way 线段与范围的相交关系筛选；提供筛选统计与节点 ID 索引。
- 通过 `bounds_of_entities` 汇总节点与完整 Way 的数据集范围；遇到缺失节点引用时报错，不推测关系几何。
- 通过 `clip_way_geometry` 将完整 Way 裁剪为矩形范围内的连续线段；相离的片段分别返回，不把范围外坐标留在裁剪结果中。
- 输出节点 Point 与 Way LineString GeoJSON，或以 JSONL 输出实体。

完整文件入口接收内存中的 `Bytes`，当前会将解码实体保存在内存中，不提供文件系统/命令行读取或增量流式 API。Way 引用缺失时保留缺失 ID，不推测坐标；含缺失节点的 Way 不通过几何范围筛选，也不会输出 GeoJSON。跨越反经线的范围不受支持。闭合 Way 不会自动解释为面，Relation 不推导多边形或多部件几何；GeoJSON 目前仅输出 Point 和 LineString。

## 示例

仓库提供内存夹具和实际文件两种示例。内存示例通过公开解码和 JSONL API 输出一个节点：

```powershell
moon run examples/decode
```

文件示例将完整 `.osm.pbf` 解码后导出为 UTF-8 JSONL，并在标准输出报告各类实体数量：

```powershell
moon run --target wasm examples/decode_file -- path/to/region.osm.pbf region.jsonl
```

预期输出：

```json
{"type":"node","id":1,"lat":0,"lon":0,"tags":{}}
```

MoonBit 宿主程序也可以先将文件内容读入 `Bytes`，然后调用完整文件解码器：

```moonbit
let limits = @moonosm.Limits::default()
match @moonosm.decode_file(pbf_bytes, limits) {
  Ok(document) => println(@moonosm.encode_jsonl(document.entities))
  Err(problem) => println(problem.to_string())
}
```

调用者可用 `NodeIndex::from_entities` 和 `select_entities_with_geometry` 执行含 Way 线段的范围筛选；对选中的完整 Way 调用 `resolve_way_geometry`、`clip_way_geometry` 获得边界内的连续线段，再将其交给目标格式序列化。`bounds_of_entities` 汇总输入节点和 Way 的经纬度范围；关系成员不会被当作已解析几何，Way 引用缺失节点时返回错误。范围无效或 Way 引用节点缺失时，裁剪 API 返回错误；无效范围也会使筛选返回空结果。完整文件解码和示例在 wasm、wasm-gc、js、native 目标上使用，文件 I/O 能力受目标运行时支持约束。端到端测试构造 OSMHeader 与 zlib OSMData 帧，验证文件解码、实体输出及损坏压缩流拒绝路径，并测试线段裁剪的边界结果。

## 检查与构建

```powershell
moon info
moon fmt --check
moon check --target all --deny-warn --warn-list=-78
moon test --target wasm
moon test --target wasm-gc
moon test --target js
moon build --target wasm
moon build --target wasm-gc
moon build --target js
moon run examples/decode
```

检查命令仅豁免 MoonBit 规则 78（建议将 `Result[T, E]` 改为异常风格返回）；解析 API 保持显式 `Result` 错误值，其他警告仍拒绝。CI 还覆盖 native；本地 Windows 环境没有 `cc`、`gcc` 或 `clang`，因此 native 目标须以远端 CI 结果验证。完整 PBF 文件读取和解压需要宿主可用内存；默认 `Limits` 及更严格的自定义上限用于限制输入消耗，不替代部署侧内存隔离。

## 参考与许可

字段映射依据 [OpenStreetMap PBF 格式说明](https://wiki.openstreetmap.org/wiki/PBF_Format) 及其 `fileformat.proto`、`osmformat.proto` schema。仓库实现自有的受限 protobuf wire reader、OSM 实体映射、查询和几何处理；未复制上游实现代码，也未捆绑 OSM 数据集夹具。项目使用 Apache-2.0 许可证，开发中使用了 AI 辅助；维护者负责最终代码审查、测试和来源合规。
