# 可复现验收

本地核验日期：2026-11-21，Windows，MoonBit `0.1.20261119`。核心库 35 项测试在 wasm、wasm-gc、js 全部通过，三个目标均完成构建；native 以公开 CI 的实际结果为准。

## 实样本与来源

输入为 [Geofabrik 的 Andorra 区域提取](https://download.geofabrik.de/europe/andorra.html)，文件 `andorra-latest.osm.pbf`，3,508,711 字节，SHA-256：

```text
3a95bb96ab66ff0859d72abb36f998c72b41e3aa13db24d3a0e0421bc61e682d
```

数据为 © OpenStreetMap contributors，适用 [ODbL](https://www.openstreetmap.org/copyright)。未将输入或导出数据提交到仓库或发布包。`latest` URL 的内容会变化，重复下载后必须检查摘要；不同快照的结果条数可能不同。

## 独立解析器差分

参考对象为 [osm-pbf-parser@2.3.0](https://github.com/substack/osm-pbf-parser)，npm 许可声明为 `MIT and LGPL`。它仅在仓库外用于测试，未复制或打包其实现。该解析器主要支持 DenseNodes，不处理普通 Node；普通 Node 的正负 ID 与坐标由本项目手工 wire 夹具单独验证。

```powershell
# REF 为仓库外的空测试目录；DATA 为包含区域快照的仓库外目录
npm install --prefix REF --no-audit --no-fund osm-pbf-parser@2.3.0
moon run --target wasm examples/decode_file -- DATA/andorra-latest.osm.pbf DATA/andorra.jsonl
node scripts/compare_reference.cjs REF DATA/andorra-latest.osm.pbf DATA/andorra.jsonl
```

已实测 529,381 条实体：501,748 个 Node、26,819 个 Way、814 个 Relation；逐条对照类型、ID、顺序、标签键值及键顺序、Way 引用、Relation 成员类型/ID/角色，节点坐标容差为 `1e-7` 度，记录差异为 0。对象元信息（版本、时间、编辑用户等）不属于本库模型，不参与对照。

## 三个完整提取流程

```powershell
moon run --target wasm examples/extract -- DATA/andorra-latest.osm.pbf DATA/cafes.geojson geojson nodes amenity cafe
moon run --target wasm examples/extract -- DATA/andorra-latest.osm.pbf DATA/residential.geojson geojson ways highway residential 42.50 1.50 42.52 1.54
moon run --target wasm examples/extract -- DATA/andorra-latest.osm.pbf DATA/routes.jsonl jsonl relations type route
python scripts/verify_extracts.py DATA
```

- 地图 POI 工作流：37 个咖啡馆 Point，ID、标签和坐标与全量差分基线一致。
- 道路 GIS 工作流：220 条命中道路，219 条非退化 GeoJSON 线；另一个 Way `399371635` 只有重合坐标，不输出零长度线。独立浮点 Liang–Barsky 实现逐条检查预期 ID，验证所有输出坐标均在边界内（容差 `1e-7` 度）及完整标签。
- 关系数据整理工作流：81 个 `type=route` Relation，JSONL 的全部字段与基线筛选结果一致，保留成员引用和角色；不推导路线几何。

这些流程以成熟 OSM 数据转换任务和格式标准为需求依据，并有真实文件输出；没有将下游用户访谈、集成部署或性能收益作为已发生事实。

## 生产代码与边界

只统计根目录非 `_test.mbt` / `_wbtest.mbt` 的生产 `.mbt` 物理行；排除示例、生成接口、文档和配置。共 2,027 行：coordinates 55、entities 554、framing 332、geometry 485、jsonl 122、moonosm 218、proto 120、query 141。含正常空行及代码注释，无填充文件。

本次验收不证明全球所有提取工具和格式扩展兼容。当前内存模型不适合直接处理 planet 全量；不支持流式输出、编辑历史、PBF 编码、LZMA/bzip2/LZ4/Zstandard Blob、Relation 面构建、反经线裁剪和路由/瓦片生成。缺失节点不能被推测成完整 Way 几何。公开错误信息保留位置和预算上下文；资源限制与拒绝路径由测试覆盖。
