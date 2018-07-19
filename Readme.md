根据Bangumi的时光机数据生成年鉴。

# 用法

```
usage: bangumi_report.py [-h] -u USER_ID [-m MAX_CONN] [-y YEAR] [-t TYPE] [-d] [--version] [-s]

-u/--user_id：指定要抓取的用户ID
-m/--max_conn：最大下载线程数
-y/--year：要生成的年份，默认为2017年。设为all将会生成所有年份
-t/--type：要抓取的的数据类型，默认为anime
-s/--saveimg: 下载图片至本地
-q/--quiet：不产生任何日志
-o/--stdout：生成的HTML将不会写入文件而是输出到stdout
```

输出文件为HTML文件~~不会写前端，太丑不用在意~~。文件名：`[user_id]-[year]-[type]-report.html`。

# Demo

[2017年](https://www.xiadong.info/html/bangumi-2017-report.html)

[All](https://www.xiadong.info/html/bangumi-all-report.html)

# 依赖
 - Requests
 - Jinja2

 # Go Server
 用刚学了两天的Go写了一个简单的HTTP server，这个脚本终于有在线版本了。但是实际上还是运行了Python脚本来生成的。

 本来是想用BGM新增加的官方API来用Go把这个脚本重写一遍，结果发现官方API没有获取全部列表的功能，只能继续用原来的脚本了。我在Go server里面都实现好了OAuth Callback和简单的数据库了发现没有卵用，以备后用还是留着吧😂。