# len.tv 接口说明（tvOS 客户端用）

来源：反编译 Android TV 客户端 `tv1.8.apk`（`com.lentv.app.data.api.ApiService`），并于 2026-10-09 用 curl 实测验证。

### 2026-10-10 热播栏目复核

从官网 `https://len.tv/download` 重新下载电视版 `tv1.8.apk` 和手机版 `m1.9.apk`，检查 DEX 导航、接口声明及手机版服务器菜单：

- 电视版有首页“热播剧集”和“热门推荐”，未发现独立的 `/trending` 页面或 API。`HomeRepository.getHotRecommendations` 使用电影、剧集的 `sort=rating` 列表合并随机推荐，与官网趋势榜不同。
- 手机版通过 `GET /menus?type=mobile` 加载菜单；实测为首页、电影、电视剧、短视频、我的，没有热播入口。其接口声明也未发现独立 trending API。
- 官网 `https://len.tv/trending` 确实存在电影、剧集混合的“趋势热播”页面。实测 `GET /api/trending` 返回 404。
- 将现有 `/movies?sort=views&page=1&pageSize=24` 与 `/tv-series?sort=views&page=1&pageSize=24` 的条目按 `view_count` 降序合并，前 24 项的类型、ID、顺序与当时官网第一页完全一致。这是当前样本的验证结果，不代表已确认官网全部排序规则。

网页 API 可行性补充（同日）：

- `https://len.tv/api/movies?sort=views&page=1&pageSize=24` 和 `https://len.tv/api/tv-series?sort=views&page=1&pageSize=24` 均返回 HTTP 200 JSON；仅携带 `Accept: application/json`，无需 Cookie 或登录令牌。字段结构与客户端现用 API 一致，首页条目 ID、顺序也一致。
- 两类接口各实测第 1–3 页，均正确返回 `page`、`pageSize`、`totalPages`、`total`，条目按 `view_count` 降序且各自无重复。合并后前 72 项与官网 `/trending`、`/trending/page/2`、`/trending/page/3` 的类型、ID、顺序全部一致。
- 官网域名的 `/api/trending?page=1&pageSize=24` 同样返回 404。当前热播 HTML 已包含完整榜单，检查该页加载的公开 JavaScript 未发现单独的热播数据请求；不能据此断言服务器内部没有相关接口。
- 可用两个现有 JSON 列表实现原生热播：分别维护电影、剧集的分页游标及剩余条目，按播放量归并输出，某一来源缓存耗尽时先补齐该来源下一页。不能直接把双方“第 N 页”合并当作热播“第 N 页”，否则会错序或遗漏。刷新时重置两路状态，条目标识保留 `kind + id`。
- 官网说明还提到点赞、收藏和更新时间，但公开前端未给出确切权重及同播放量时的次序。以上验证证明当前样本一致，不保证播放量相同或官网算法调整后的排序完全一致。

客户端现已通过 `LenAPIClient.trending(after:)` 实现上述归并，每批最多 24 项，沿用现有 API 域名（已核对与网页域名列表一致）。同播放量时先取电影，并保留各来源原有次序；统计字段仅参与排序，不展示在卡片上。游标为值类型，请求失败后可原样重试；新一轮刷新不传游标，跳过本地 HTTP 缓存。

本次 APK SHA-256：

```text
tv1.8.apk f6346ed3785e909bcfeae19d6f06a039f39ffa68221c08e33a6fd7d36a447ae5
m1.9.apk  3df7a6408f7740944fe067b1cf7f483d4a08d59a220afbf68ca9cb39c678cd2e
```

## 通用

- Base URL：`https://apiii.solada.site/api/`（写死在 `AppContainer.baseUrl`）
- 请求头：`Accept: application/json`。登录后另加 `Authorization: Bearer <token>`。搜索和播放不需要登录。
- 没有签名、时间戳或加密参数。

## 1. 搜索

```
GET /search?q=<关键词>&type=all|movie|tv&page=1&pageSize=20
```

- `type` 默认为 `all`。实测服务端会忽略 `pageSize`，一次返回全部结果（`total == pageSize`）。
- 响应：

```json
{
  "total": 31, "page": 1, "pageSize": 31, "keyword": "蜘蛛侠",
  "results": [
    {
      "id": 40614, "title": "蜘蛛侠：崭新之日", "poster": "https://...jpg",
      "year": 2026, "rating": "10.0", "director": "...", "actors": "a,b,c",
      "region": "美国", "total_episodes": 1, "current_episode": 1,
      "resultType": "movie",          // "movie" | "tv"
      "url": "/vod/movie-蜘蛛侠-崭新之日-2026-40614"
    }
  ]
}
```

## 2. 详情（包含所有线路和每集的播放地址）

```
GET /movies/{id}        // resultType == "movie"
GET /tv-series/{id}     // resultType == "tv"
```

响应格式为 `{ "success": true, "data": {...} }`。播放只需要 `data.source_options`：

```json
"source_options": [
  {
    "key": "0:141487",            // 线路 key，切换线路或调用 play-url 时作为 source 参数
    "name": "豆瓣",                // 线路名
    "sourceId": "141487",
    "episodes": [
      { "id": 1, "number": 1, "season": 1, "title": "正片",
        "videoUrl": "https://vodcnd17.ajupf.com/20261006/OaWhoNqF/index.m3u8",
        "isAvailable": true }
    ]
  },
  { "key": "1:117072", "name": "速博", "episodes": [ ... ] },
  { "key": "2:152730", "name": "红牛", "episodes": [ ... ] }
]
```

其他常用字段：`title`、`poster`、`backdrop`、`year`、`region`、`director`、`actors`、`description`、`total_episodes`、`current_episode`、`is_finished`。

## 3. 单独获取播放地址（可选，作为兜底）

当详情里的 `videoUrl` 为空，或者想拿到最新地址时调用：

```
GET /movies/{id}/play-url?source=<key>
GET /tv-series/{id}/episodes/{episodeNumber}/play-url?source=<key>
```

```json
{ "success": true,
  "data": { "url": "https://hn.bfvvs.com/play/axklJyqe/index.m3u8", "type": "direct",
            "source_key": "2:152730", "source_name": "红牛", "source_id": "152730" } }
```

电视剧的响应里还有 `episode`、`episode_id`、`tv_series_id` 字段。

## 4. 首页

```
GET /home
```

不带 success/data 外壳。客户端只用到其中两个字段：
- `movies`：热门电影，12 部。字段有 `id, title, poster, release_date, region, director, actors, description, rating, category_name`
- `tvSeries`：热门剧集，12 部。字段有 `id, title, poster, first_air_date, region, total_episodes, current_episodes, category_name, description`

另有 `reviews / shortVideos / authors / adsByPosition`（影评、短视频、作者、广告），客户端不使用。

## 5. 分类列表（电影 / 剧集页）

```
GET /movies?page=1&pageSize=30&type=<分类slug>&region=<地区>&year=<年份>&sort=<排序>
GET /tv-series?page=1&pageSize=30&type=<分类slug>&region=<地区>&year=<年份>&isFinished=<bool>&sort=<排序>
```

- 响应：`{ success, data: { items: [...], total, page, pageSize, totalPages } }`
- `type` 要传 **slug**，不是中文名（例如传 `type=动作` 会返回 0 条）：
  - 电影分类 `GET /categories?type=movie`：动作 action、喜剧 comedy、剧情 drama、科幻 sci-fi、爱情 romance、悬疑 mystery、恐怖 horror、动画 animation
  - 剧集分类 `GET /categories?type=tv`：国产剧 chinese-drama、欧美剧 american-drama、韩剧 korean-drama、日剧 japanese-drama、港台剧 hk-tw-drama、泰剧 thai、动漫 dongman
- `sort`：`latest`（剧集按最近更新排序）、`views`（最热）、`rating`（评分）。传不认识的值时会按默认排序返回。
- `region`：取值来自 `GET /regions`，有大陆、香港、台湾、美国、日本、韩国、英国、法国、德国、印度、泰国、其他。注意数据里的地区写法不统一（例如"大陆"和"中国大陆"混用），筛选结果可能不全。
- `year`：取值来自 `GET /years`，返回 `[{ "year": "2026" }, …, { "year": "earlier-2015" }]`。
- 实测：国产剧共 7661 部，动作电影共 5602 部。

## 播放

- 线路都是标准 HLS（m3u8）。部分线路使用 `#EXT-X-KEY:METHOD=AES-128` 标准加密，AVPlayer 可以原生处理。
- 实测不需要 Referer 或特殊的 User-Agent，`AVPlayer(url:)` 可以直接播放。
- 线路来自第三方资源站，可能失效。播放失败时应自动或手动切换到下一条 `source_options`。
