# MoonOSM 选题与语义查重

核验日期：2026-11-20。范围是公开索引与已检查仓库，不是主办方结论，也不证明生态内绝对唯一。所有候选均按用户任务、输入、核心语义和输出比较，不按名称判断。

## 候选与选择

| 候选方向 | 用户任务与成熟基线 | 已查相邻项目 | 结论 |
|---|---|---|---|
| OSM PBF 解码与筛选 | 将 OSM PBF 文件帧、Blob、PrimitiveBlock 解码为节点/Way/Relation；基线为 OSM PBF schema 与 protobuf wire 规则 | `t-ujiie-g/pbf` 通用 protobuf wire；`yyyt0807/moonmvt` Mapbox Vector Tile；`Suquster/moonbit-pathfinding` OSM edge-list 路由 | 选定：文件格式、实体模型与输入输出不同；实样本差分与三个提取流程已完成 |
| G-code 读写/校验 | 解析制造指令并检查方言语义，成熟基线是 G-code 方言与刀路工作流 | `cjcjwe/gcode-toolkit` | 淘汰：领域工具已有直接功能重合，独立再造价值不足 |
| miniSEED 波形读取 | 读取地震台站记录、时间/采样元数据和波形数据，基线为 miniSEED 记录格式 | `hzc-666-ai/moonseis` 与注册表 MoonSeis | 淘汰：已有领域项目覆盖该任务 |

## 查询记录

本机 MoonBit CLI：

- `moon search osm --limit 100`：2 个结果；其中 `Suquster/moonbit-pathfinding@0.2.0` 描述 OSM edge-list 装载/寻路，不是 PBF 文件解码。
- `moon search openstreetmap --limit 100`：无结果。
- `moon search pbf --limit 100`：包含 `t-ujiie-g/pbf@0.1.0`（通用 protobuf wire）及 `t-ujiie-g/mvt@0.1.0`（MVT）。
- `moon search geospatial --limit 100`：17 个相邻地理空间模块，覆盖 WKT/WKB/GeoJSON、H3、FlatGeobuf、KML、LAS、MVT、Shapefile、路线等；未见专门 OSM PBF 解码器。
- `moon search "openstreetmap pbf" --limit 100`、`moon search "osm pbf decoder" --limit 100`：均无结果。
- `moon search "geospatial import" --limit 100`：5 个泛 GIS/地理数据候选，包括 `Duan-lang-dev/moonecoguard@0.1.0`、`moyunijieshi1/moon-flatgeobuf@0.3.0`、`cp156955/moonkml@0.3.0`、`liyun6666/moon-shapefile@0.1.1`、`JIA2JIA2/moonbitgeodb@0.1.7`。

绑定账号 `JiangBowen08` 下 GitHub API 搜索仓库：

- `search/repositories?q=OpenStreetMap+PBF+language:MoonBit&per_page=100`：0 项，`incomplete_results=false`。
- `search/repositories?q=OSM+decoder+MoonBit&per_page=100`：0 项，`incomplete_results=false`。
- `search/repositories?q=geospatial+MoonBit&per_page=100`：5 项，`incomplete_results=false`；其中 H3、GPX 与通用地理格式实现属于相邻能力。
- 对目标 `JiangBowen08/moonosm` 的 GitHub repository API 查询返回 HTTP 404；这是仓库创建前核验，不是查重结论。

## 源码边界对照

| 项目 | 检查到的实现边界 | 与 MoonOSM 的关系 |
|---|---|---|
| `t-ujiie-g/pbf@0.1.0` | MoonCakes 描述为通用 protobuf wire reader/writer；协议层可复用但不提供 OSM Header、Blob/PrimitiveBlock 与实体语义 | 低度相邻；当前代码自行处理受限 PBF 子集，未来应评估复用而非复制 |
| `yyyt0807/moonmvt@0.1.1` | 仓库 `MoonMVT` 的 `codec/decode.mbt`、`geometry/`、`model/`、`query/`、`tests/` 实现 Mapbox Vector Tiles | 输入格式及 tile 模型不同；不是 OSM PBF Reader |
| `Suquster/moonbit-pathfinding@0.2.0` | 仓库 `moonbit-pathfinding` 的 `src/graph/osm.mbt` 读取 OSM edge-list 并构建路由图 | 消费已整理的边列表并寻路；不解析 PBF 原始节点、标签和 Relation |
| `moyunijieshi1/moon-flatgeobuf@0.3.0` | MoonCakes 说明覆盖 FlatGeobuf 二进制读写、索引/远程范围查询与 GeoJSON 互操作 | 地理二进制容器相邻，schema 与语义不同 |
| `cp156955/moonkml@0.3.0`、`liyun6666/moon-shapefile@0.1.1` | 分别处理 KML/KMZ XML 与 Shapefile 几何/属性表 | 其他交换格式，不读取 OSM PBF |

来源入口：

- OSM PBF 格式：<https://wiki.openstreetmap.org/wiki/PBF_Format>
- 通用 PBF MoonCakes：<https://mooncakes.io/docs/t-ujiie-g/pbf@0.1.0>
- MoonMVT 源码：<https://github.com/yyyt0807/MoonMVT>
- OSM 路由源码：<https://github.com/Suquster/moonbit-pathfinding>
- FlatGeobuf：<https://mooncakes.io/docs/moyunijieshi1/moon-flatgeobuf@0.3.0>
- KML：<https://mooncakes.io/docs/cp156955/moonkml@0.3.0>
- Shapefile：<https://mooncakes.io/docs/liyun6666/moon-shapefile@0.1.1>

## 交付前反向复核（2026-11-20）

项目功能定型后，以升级后的 MoonBit `0.1.20261119` 重新运行 MoonCakes 公开搜索：

- `moon search osm --limit 100`：2 项，含 `Suquster/moonbit-pathfinding@0.2.0` 的 OSM edge-list 装载/路由；另一个膜分离项目与本域无关。
- `moon search openstreetmap --limit 100`：无结果。
- `moon search pbf --limit 100`：`t-ujiie-g/pbf@0.1.0` 通用 Protobuf wire reader/writer、`t-ujiie-g/mvt@0.1.0` Mapbox Vector Tile decoder；均不实现 OSM PBF 实体模型。
- `moon search 'osm decoder' --limit 100`：仅返回上述 edge-list 路由项目。
- `moon search geospatial --limit 100`：17 个地理空间相邻项目，包括 GeoJSON/WKT/WKB、MVT、H3、FlatGeobuf、Shapefile、KML、LAS、路线与空间索引等。
- `moon search 'select_entities_with_geometry' --limit 100`：5 个结果，均为通用几何、GUI 或图算法模块，未见相同 OSM PBF 输入/实体语义。

对核心 API/行为反向查找并结合前述源码边界，查重指纹包括 PBF 文件帧/Blob 的 raw 与 zlib 解码、`OSMHeader` required-feature 校验、PrimitiveBlock 实体、`NodeIndex`、Way 线段矩形相交与 `clip_way_geometry`、JSONL/GeoJSON 输出。已识别的近邻仍按上表分类：通用 Protobuf 可作为底层依赖候选；MVT 的 tile 字节模型、OSM edge-list 路由的输入数据和图算法均不同。没有发现 MoonCakes 已发布的直接 OSM PBF reader。搜索是公开索引查询，不覆盖私有仓库、未索引项目或其他语言中潜在实现；该结果不等于绝对唯一或主办方认定。

实现范围已增加完整文件内 raw/zlib Blob 解码、矩形 Way 裁剪与范围内 GeoJSON。2026-11-20 使用公开 Andorra 区域 `andorra-latest.osm.pbf`（3,508,711 字节）对照独立 npm 解析器 `osm-pbf-parser@2.3.0`：两边输出均为 529,381 个实体（node 501,748、way 26,819、relation 814），按实体顺序及类型/ID、节点坐标、Way 引用、Relation 成员（类型/ID/角色）、标签键值与顺序逐条比较，共 0 条记录差异。坐标差分容差为 `1e-7` 度；样本导出保存在本机临时目录，不纳入仓库。该实验验证的是这一份 Andorra 样本，不等同于所有 PBF 扩展与压缩编码均兼容，也不能证明真实下游用户需求。

## 需求依据与完成标准

目前记录范围内未发现成熟的直接 OSM PBF 解码替代；通用 protobuf、MVT、路由图、FlatGeobuf、KML 与 Shapefile 均有不同核心任务。代码与 OSM PBF schema 独立实现，测试夹具为手写的最小 protobuf 字节，不含复制的数据集。

需求以 OSM PBF schema、Geofabrik 区域数据分发及成熟工具的提取/导出工作流为依据，不声称已访谈用户。三个实际闭环为：地图作者输入区域 PBF、筛 `amenity=cafe`、得到点 GeoJSON；GIS 分析者输入同一区域、筛住宅道路并裁剪矩形、得到可用线 GeoJSON；关系数据整理者筛 `type=route`、得到保留成员类型/ID/角色的 JSONL。相较只提供 protobuf wire、MVT 或边列表路由，用户无需自行实现 PBF framing、DenseNodes/delta、字符串表、坐标映射和节点引用解析。

本次完成标准是 raw/zlib 文件解码、受限且可诊断的实体模型、节点索引与线段裁剪、独立标签/类型过滤、JSONL/GeoJSON 输出以及三个实际文件流程。已通过 529,381 条实体的独立解析器逐字段差分（0 条记录差异），三流程得到 37 个点、219 条有效线、81 个关系；输入摘要、许可、复现步骤和特殊退化 Way 见 [验收说明](../validation.md)。独立解析器和流程证据满足本次实现验收；不将其外推为市场验证、完整格式兼容或真实用户部署。

2026-11-21 再次执行 `moon search osm/openstreetmap/pbf --limit 100`：结果分别为 2/0/2，仍为膜分离、edge-list 路由、通用 wire 与 MVT 项目，未出现记录范围内的直接 OSM PBF 实体读取替代。GitHub 与 MoonCakes 索引均有边界；源码对照只覆盖表列文件与行为，没有穷尽全部历史。当前范围未发现成熟直接替代；发现维护中的同任务实现时，应重新评估扩展协作。
