#! /usr/bin/env python3

import os
import argparse
import logging
import re
from threading import BoundedSemaphore, Thread, active_count
import datetime
import json

import requests


class ImageURLList:
    def __init__(self, user_id, max_connection, year, type, saveimg):
        self.user_id = user_id
        self.item_url_list = []
        self.pool_sema = BoundedSemaphore(value=max_connection)
        self.year = year
        self.type = type
        self.saveimg = saveimg
        self.session = requests.Session()
        self.session.headers = {'User-Agent': 'Mozilla/5.0 Chrome/77.0.3865.120'}

    def save_img(self, img_url, file_path='img'):
        try:
            if not os.path.exists(file_path):
                logging.info('Folder "%s" unexisted, recreated',file_path)
                os.makedirs(file_path)
            file_suffix = os.path.splitext(img_url)[1]
            file_name = img_url.split("/")[-1]
            filename = '{}{}{}{}'.format(file_path,os.sep,file_name,file_suffix)
            logging.debug('image saved: %s',filename)
            im = self.session.get(img_url)
            if im.status_code == 200:
                open(filename,'wb').write(im.content)
            return filename
        except IOError as e: logging.error('IOError : %s',e)
        except Exception as e: logging.error('Error : %s',e)

    def get_missed_image (self, item_id):
        bgm_api_prefix = 'http://api.bgm.tv'
        item_url = bgm_api_prefix + '/subject/' + item_id
        default_ret = '//bgm.tv/img/no_icon_subject.png'

        response = self.session.get(item_url)
        if response.status_code != 200:
            logging.error('\nURL: %s\nStatus code: %s\nContent: %s\n', \
                item_url, response.status_code, response.text)
            return default_ret
        res_json = json.loads(response.text)
        if 'images' not in res_json or 'large' not in res_json['images']:
            return default_ret
        return res_json['images']['large'][5:]

    def get_item_url(self, page_url, type):
        with self.pool_sema:
            logging.debug('Parsing %s', page_url)
            response = self.session.get(page_url)
            if response.status_code != 200:
                logging.error('\nURL: %s\nStatus code: %s\nContent: %s\n', \
                    page_url, response.status_code, response.text)
                return

            pattern = re.compile(r'<img src="(.*?)" class="cover" />.*?<a href="(/subject/\d+?)" class="l">(.*?)</a>.*?(<span class="starstop-s"><span class="starlight stars(\d+?)"></span></span>)?<span class="tip_j">(\d{4}-\d{1,2}-\d{1,2})</span>', re.S)
            # item image_url, link, title, [wtf], starinfo, marked_time
            response.encoding = 'utf-8'
            items = pattern.findall(response.text)
            logging.debug('%s items in %s', len(items), page_url)

            page_idx = int(page_url.split('?page=')[1]) - 1
            folder_path = '%s-%s-%s-report' % (self.user_id, self.year, self.type)
            for item in items:
                if self.year != 'all' and item[5][0:4] != self.year:
                    continue
                large_image_url = item[0].replace('/s/', '/l/')
                # The image is not shown to guest. Use API to get it
                if large_image_url.startswith('/img/'):
                    item_id = item[1].split('/')[-1]
                    large_image_url = self.get_missed_image(item_id)
                img_url = 'https:' + large_image_url
                if self.saveimg:
                    img_url = self.save_img(img_url, folder_path)
                marked_time = datetime.datetime.strptime(item[5], '%Y-%m-%d')
                star_num = -1
                if item[4] != '':
                    star_num = int(item[4])
                self.item_url_list_page[page_idx].append({
                    'image_url': img_url,
                    'marked_date': marked_time.strftime('%Y-%m-%d'),
                    'title': item[2],
                    'link': 'http://bgm.tv' + item[1],
                    'star': star_num,
                    'type': type
                })

    def get_list_type(self, type):
        list_url = "http://bgm.tv/%s/list/%s" % (type, self.user_id)
        collect_url = list_url + '/collect'
        logging.info('Starting collect type of %s', type)
        logging.debug('collect_url=%s', collect_url)

        page_num = 0
        response = self.session.get(collect_url)
        if response.status_code != 200:
            logging.error('\nStatus code: %s\nContent: %s\n', response.status_code, response.text)
            return

        pattern = re.compile(r'.*&nbsp;(\d+)&nbsp;/&nbsp;(\d+)&nbsp;.*')
        matches = pattern.findall(response.text)
        if not matches:
            pattern = re.compile(r'(<a href="/anime/list/.*?>\d+</a>)')
            matches = pattern.findall(response.text)
            page_num = len(matches) + 1
        else:
            logging.debug('matches=%s', matches)
            page_num = int(matches[0][1])

        logging.info('page_num=%s', page_num)
        logging.info('Getting item URLs')

        url_prefix = collect_url + '?page='
        page_list = [url_prefix + str(x) for x in range(1, page_num + 1)]
        page_list.reverse()

        self.item_url_list_page = [[] for i in range(page_num)]

        thread_list = []
        for page_url in page_list:
            thread = Thread(target=self.get_item_url, kwargs={'page_url': page_url, 'type': type})
            thread_list.append(thread)
            thread.start()

        thread_num = len(thread_list)
        for i in range(thread_num):
            thread_list[i].join()
            this_page_idx = thread_num - i - 1
            self.item_url_list += self.item_url_list_page[this_page_idx][::-1]
            logging.info('Finished: %s/%s', i + 1, thread_num)

        del self.item_url_list_page

    def get_list(self):
        if self.type == 'all':
            for type in ['anime', 'book', 'music', 'game', 'real']:
                self.get_list_type(type)
        else:
            self.get_list_type(self.type)

        # print(self.item_url_list)
        logging.info('Finished getting item URLs. Got %s items', len(self.item_url_list))
        return self.item_url_list


class ReportGenerator:
    def __init__(self, image_url_list, user_id, year, type):
        self.image_url_list = []
        image_url_list.sort(key=lambda image: image['marked_date'])

        curr_month = '00'
        for image in image_url_list:
            if image['marked_date'][5:7] != curr_month:
                image['label'] = int(image['marked_date'][5:7])
                curr_month = image['marked_date'][5:7]
            else:
                image['label'] = 0
        curr_year = '0000'
        tmp_list = []
        for image in image_url_list:
            if image['marked_date'][0:4] != curr_year:
                if tmp_list:
                    self.image_url_list.append(tmp_list)
                tmp_list = [image]
                curr_year = image['marked_date'][0:4]
            else:
                tmp_list.append(image)
        if tmp_list:
            self.image_url_list.append(tmp_list)

        self.user_id = user_id
        self.year = year
        self.type = type

    def generate_html(self, to_stdout):
        from jinja2 import Environment, FileSystemLoader  # only import when generating HTML
        self.env = Environment(loader=FileSystemLoader(os.getcwd()))
        logging.debug('Template file: %s', 'template.html')
        template = self.env.get_template('template.html')
        html = template.render(
            user_id=self.user_id, image_list=self.image_url_list, year=self.year, type=self.type)
        if not to_stdout:
            with open(self.file_name, 'w', encoding='utf-8') as f:
                f.write(html)
        else:
            print(html)

    def generate_markdown(self):
        text = '# Bangumi List\n'
        scorings = self.image_url_list.copy()
        for items_in_same_year in scorings:
            for item in items_in_same_year:
                item['marked_year'] = int(item['marked_date'][0:4])
                item['marked_month'] = int(item['marked_date'][5:7])
        for items_in_same_year in scorings:
            if items_in_same_year:
                text += '\n## %s 年 (完成 %d 部作品)\n' % (
                    items_in_same_year[0]['marked_year'], len(items_in_same_year))
            else:
                continue
            items_in_same_month_dict = {k: [] for k in range(1, 13)}
            for item in items_in_same_year:
                items_in_same_month_dict[item['marked_month']].append(item)
            for month in items_in_same_month_dict:
                items_per_month = items_in_same_month_dict[month]
                text += '\n### %d 月 (完成 %d 部作品)\n' % (month,
                                                      len(items_per_month))
                star_agg = {item['star']: [] for item in items_per_month}
                for item in items_per_month:
                    star_agg[item['star']].append(item)
                for star in sorted(star_agg.keys(), reverse=True):
                    items_with_same_star = star_agg[star]
                    if star > 0:
                        text += '\n%d 分 (%d 部作品)\n\n' % (star,
                                                         len(items_with_same_star))
                    else:
                        text += '\n未评分 (%d 部作品)\n\n' % (len(items_with_same_star))
                    for item in items_with_same_star:
                        text += '- %s\n' % (item['title'])
        with open(self.file_name, 'w', encoding='utf-8') as f:
            f.write(text)

    def generate_report(self, to_stdout, markdown):
        self.file_name = '%s-%s-%s-report.%s' % (
            self.user_id, self.year, self.type, 'html' if not markdown else 'md')
        logging.info('Output file: %s', self.file_name)
        if not markdown:
            self.generate_html(to_stdout)
        else:
            self.generate_markdown()


def main():
    parser = argparse.ArgumentParser(description='Generate Bangumi user report.')
    parser.add_argument('-u', '--user_id', type=str, required=True)
    parser.add_argument('-m', '--max_conn', type=int, default=5)
    parser.add_argument('-y', '--year', type=str, default=str(datetime.datetime.now().year))
    parser.add_argument('-t', '--type', type=str, default='anime',
                        help='report type from: all, anime, book, music, game, real')
    parser.add_argument('-d', '--debug', action='store_true', default=False)
    parser.add_argument('--version', action='version', version='%(prog)s 0.1')
    parser.add_argument('-s', '--saveimg', action='store_true', default=False)
    parser.add_argument('-o', '--stdout', action='store_true', default=False)
    parser.add_argument('-q', '--quiet', action='store_true', default=False)
    parser.add_argument('-md', '--markdown', action='store_true', default=False)

    args = parser.parse_args()
    if args.quiet:
        logging.basicConfig(level=logging.CRITICAL)
    elif args.debug:
        logging.basicConfig(level=logging.DEBUG, \
                    format='[%(asctime)s][%(filename)s][%(lineno)s][%(levelname)s][%(process)d][%(message)s]')
    else:
        logging.basicConfig(level=logging.INFO, \
                    format='[%(asctime)s][%(levelname)s][%(message)s]')

    logging.info('user_id=\'%s\', max_conn=%s, year=%s, type=%s', args.user_id, args.max_conn, args.year, args.type)

    image_url_list = ImageURLList(args.user_id, args.max_conn, args.year, args.type, args.saveimg).get_list()
    report_generator = ReportGenerator(image_url_list, args.user_id, args.year, args.type)
    report_generator.generate_report(args.stdout, args.markdown)

if __name__ == '__main__':
    main()
