import argparse
from html.parser import HTMLParser
import json
from pathlib import Path
import re
import sys
import urllib.error
import urllib.request


class PageText(HTMLParser):
    def __init__(self):
        super().__init__()
        self.parts = []

    def handle_data(self, data):
        self.parts.append(data)


def latest_version(target):
    url = {
        'ruby': 'https://www.ruby-lang.org/en/downloads/',
        'fil-c': 'https://api.github.com/repos/pizlonator/fil-c/releases/latest',
    }[target]
    request = urllib.request.Request(url, headers={'User-Agent': 'ruby-filc-version-lint'})
    with urllib.request.urlopen(request, timeout=20) as response:
        body = response.read().decode('utf-8')
    if target == 'ruby':
        page = PageText()
        page.feed(body)
        versions = re.findall(r'current stable version is\s+(\d+\.\d+\.\d+)\b', ' '.join(page.parts))
        if len(versions) != 1:
            raise ValueError('Ruby downloads page must identify exactly one current stable version')
        return versions[0]
    release = json.loads(body)
    if not isinstance(release, dict) or release.get('draft') is not False or release.get('prerelease') is not False:
        raise ValueError('Fil-C latest release must be a published stable release')
    tag = release.get('tag_name')
    if not isinstance(tag, str) or not re.fullmatch(r'v\d+(?:\.\d+)+', tag):
        raise ValueError('Fil-C latest release has an invalid version tag')
    return tag.removeprefix('v')


def main():
    parser = argparse.ArgumentParser(description='Check the Docker build pin against the latest stable upstream release.')
    parser.add_argument('target', choices=['ruby', 'fil-c'])
    args = parser.parse_args()
    name = {'ruby': 'RUBY_VERSION', 'fil-c': 'FILC_VERSION'}[args.target]
    try:
        dockerfile = Path(__file__).resolve().parents[1] / 'example/Dockerfile'
        pins = re.findall(rf'^ARG {name}=(\d+(?:\.\d+)+)$', dockerfile.read_text(), re.MULTILINE)
        if len(pins) != 1:
            raise ValueError(f'{dockerfile} must contain exactly one numeric {name} pin')
        latest = latest_version(args.target)
    except (OSError, ValueError, urllib.error.URLError) as error:
        print(f'{args.target}: cannot verify latest stable release: {error}', file=sys.stderr)
        return 2
    if pins[0] != latest:
        print(f'{args.target}: pinned {pins[0]}, latest stable {latest}; update the build pin, checksums and port before committing', file=sys.stderr)
        return 1
    print(f'{args.target}: {pins[0]} is the latest stable release')
    return 0


if __name__ == '__main__':
    sys.exit(main())
