根据Bangumi的时光机数据生成年鉴。

# 用法

```
usage: bangumi_report.py [-h] -u USER_ID [-m MAX_CONN] [-y YEAR] [-t TYPE] [-d] [--version] [-s]

-u/--user_id：指定要抓取的用户ID
-m/--max_conn：最大下载线程数
-y/--year：要生成的年份，默认为2017年。设为all将会生成所有年份
-t/--type：要抓取的的数据类型，默认为anime
-s/--saveimg: 下载图片至本地
```

输出文件为HTML文件~~不会写前端，太丑不用在意~~。文件名：`[user_id]-[year]-[type]-report.html`。

# Demo

[2017年](https://www.xiadong.info/html/bangumi-2017-report.html)

[All](https://www.xiadong.info/html/bangumi-all-report.html)

# 依赖
 - Requests
 - Jinja2
