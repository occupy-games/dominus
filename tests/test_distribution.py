import hashlib
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from tools.setup_content import download

ROOT=Path(__file__).resolve().parents[1]


class Response(io.BytesIO):
    def __init__(self,body,status):super().__init__(body);self.status=status


class DistributionTests(unittest.TestCase):
    def test_download_verifies_and_reuses_content_without_another_request(self):
        payload=b'verified external archive'
        spec=dict(url='https://example.test/content.7z',bytes=len(payload),sha1=hashlib.sha1(payload).hexdigest())
        with tempfile.TemporaryDirectory() as directory:
            path=Path(directory)/'original.7z'
            with patch('tools.setup_content.urllib.request.urlopen',return_value=Response(payload,200)) as request:
                download(spec,path,lambda *args:None)
                download(spec,path,lambda *args:None)
                self.assertEqual(request.call_count,1)
            self.assertEqual(path.read_bytes(),payload)

    def test_partial_response_resumes_but_a_full_response_restarts(self):
        payload=b'0123456789'
        spec=dict(url='https://example.test/content.7z',bytes=len(payload),sha1=hashlib.sha1(payload).hexdigest())
        for status,body in [(206,payload[4:]),(200,payload)]:
            with tempfile.TemporaryDirectory() as directory:
                path=Path(directory)/'original.7z';path.with_suffix('.partial').write_bytes(payload[:4])
                with patch('tools.setup_content.urllib.request.urlopen',return_value=Response(body,status)):
                    download(spec,path,lambda *args:None)
                self.assertEqual(path.read_bytes(),payload)

    def test_bad_download_cannot_become_installed_content(self):
        spec=dict(url='https://example.test/content.7z',bytes=4,sha1=hashlib.sha1(b'good').hexdigest())
        with tempfile.TemporaryDirectory() as directory:
            path=Path(directory)/'original.7z'
            with patch('tools.setup_content.urllib.request.urlopen',return_value=Response(b'bad!',200)):
                with self.assertRaises(ValueError):download(spec,path,lambda *args:None)
            self.assertFalse(path.exists())

    def test_a_completed_partial_is_verified_without_a_range_request(self):
        payload=b'complete archive'
        spec=dict(url='https://example.test/content.7z',bytes=len(payload),sha1=hashlib.sha1(payload).hexdigest())
        with tempfile.TemporaryDirectory() as directory:
            path=Path(directory)/'original.7z';path.with_suffix('.partial').write_bytes(payload)
            with patch('tools.setup_content.urllib.request.urlopen') as request:
                download(spec,path,lambda *args:None)
                request.assert_not_called()
            self.assertEqual(path.read_bytes(),payload)

    def test_source_configuration_and_exclusions_are_explicit(self):
        spec=json.loads((ROOT/'config/asset_source.json').read_text())
        self.assertEqual(spec['bytes'],472291771)
        self.assertEqual(spec['sha1'],'4e3fafd65ac04394c932b5ef7e99d66ef7da9220')
        self.assertTrue(spec['url'].startswith('https://archive.org/download/'))
        ignore=(ROOT/'.gitignore').read_text().splitlines()
        for path in ['/data/','/dist/','/game/assets/original/','/game/assets/extracted/','/game/assets/library/']:self.assertIn(path,ignore)


if __name__=='__main__':unittest.main()
