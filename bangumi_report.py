#! /usr/bin/env python3

import os
import argparse
import logging
import re
from threading import BoundedSemaphore, Thread, active_count
import datetime

import requests
from jinja2 import Environment, FileSystemLoader

class ImageURLList:
    def __init__(self, user_id, max_connection, year):
        self.user_id = user_id
        self.item_url_list = []
        self.pool_sema = BoundedSemaphore(value=max_connection)
        self.year = year

    def get_item_url(self, page_url):
        with self.pool_sema:
            logging.debug('Parsing %s', page_url)
            response = requests.get(page_url)
            if response.status_code != 200:
                logging.error('\nURL: %s\nStatus code: %s\nContent: %s\n', \
                    page_url, response.status_code, response.text)
                return

            pattern = re.compile(r'<img src="(.*?)" class="cover" />.*?<a href="(/subject/\d+?)" class="l">(.*?)</a>.*?<span class="tip_j">(\d{4}-\d{1,2}-\d{1,2})</span>', re.S)
            response.encoding = 'utf-8'
            items = pattern.findall(response.text)
            logging.debug('%s items in %s', len(items), page_url)

            for item in items:
                if self.year != 'all' and item[3][0:4] != self.year:
                    continue
                large_image_url = item[0].replace('/s/', '/l/')
                marked_time = datetime.datetime.strptime(item[3], '%Y-%m-%d')
                self.item_url_list.append({
                    'image_url': 'https:' + large_image_url, 
                    'marked_date': marked_time.strftime('%Y-%m-%d'),
                    'title': item[2],
                    'link': 'http://bgm.tv' + item[1]
                })

    def get_list(self):
        collect_url = "http://bgm.tv/anime/list/%s/collect" % self.user_id
        logging.debug('collect_url=%s', collect_url)

        page_num = 0
        response = requests.get(collect_url)
        if response.status_code != 200:
            logging.error('\nStatus code: %s\nContent: %s\n', response.status_code, response.text)
            return self.image_url_list

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

        url_prefix = 'http://bgm.tv/anime/list/%s/collect?page=' % self.user_id
        page_list = [url_prefix + str(x) for x in range(1, page_num + 1)]
        
        thread_list = []
        for page_url in page_list:
            thread = Thread(target=self.get_item_url, kwargs={'page_url': page_url})
            thread_list.append(thread)
            thread.start()
        
        thread_num = len(thread_list)
        for thread in thread_list:
            thread.join()
            logging.info('Finished: %s/%s', thread_num - active_count(), thread_num)

        # print(self.item_url_list)
        logging.info('Finished getting item URLs. Got %s items', len(self.item_url_list))
        return self.item_url_list
 

class ReportGenerator:
    def __init__(self, image_url_list, user_id, year):
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

        self.env = Environment(loader=FileSystemLoader(os.getcwd()))
        self.user_id = user_id
        self.year = year

    def generate_report(self):
        file_name = '%s-%s-report.html' % (self.user_id, self.year)
        logging.info('Output file: %s', file_name)
        logging.debug('Template file: %s', 'template.html')
        template = self.env.get_template('template.html')
        with open(file_name, 'w', encoding='utf-8') as f:
            f.write(template.render(user_id=self.user_id, image_list=self.image_url_list, year=self.year))


def main():
    parser = argparse.ArgumentParser(description='Generate Bangumi user report.')
    parser.add_argument('-u', '--user_id', type=str, required=True)
    parser.add_argument('-m', '--max_conn', type=int, default=5)
    parser.add_argument('-y', '--year', type=str, default='2017')
    parser.add_argument('-d', '--debug', action='store_true', default=False)
    parser.add_argument('--version', action='version', version='%(prog)s 0.1')

    args = parser.parse_args()
    if args.debug:
        logging.basicConfig(level=logging.DEBUG, \
                    format='[%(asctime)s][%(filename)s][%(lineno)s][%(levelname)s][%(process)d][%(message)s]')
    else:
        logging.basicConfig(level=logging.INFO, \
                    format='[%(asctime)s][%(levelname)s][%(message)s]')

    logging.info('user_id=\'%s\', max_conn=%s, year=%s', args.user_id, args.max_conn, args.year)

    image_url_list = ImageURLList(args.user_id, args.max_conn, args.year).get_list()
    report_generator = ReportGenerator(image_url_list, args.user_id, args.year)
    report_generator.generate_report()

if __name__ == '__main__':
    main()
