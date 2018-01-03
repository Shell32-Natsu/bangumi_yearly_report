根据Bangumi的时光机数据生成年鉴。目前只支持动画。

# 用法

```
usage: bangumi_report.py [-h] -u USER_ID [-m MAX_CONN] [-y YEAR] [-d] [--version]

-u/--user_id：指定要抓取的用户ID
-m/--max_conn：最大下载线程数
-y/--year：要生成的年份，默认为2017年
```

输出文件为HTML文件~~不会写前端，太丑不用在意~~。文件名：`[user_id]-[year]-report.html`。

# Demo

<https://www.xiadong.info/html/bangumi-2017-report.html>

# 依赖
 - Requests
 - Jinja2