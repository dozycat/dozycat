"""Appcast publication guards; no Keychain access or real releases required."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / 'make-appcast.sh'
FEED = '''<?xml version="1.0"?>
<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel>
<item>
<sparkle:shortVersionString>0.1.5</sparkle:shortVersionString>
<enclosure url="https://example.com/__VERSION__/dozycat-0.1.5-arm64.dmg" sparkle:edSignature="fixture"/>
<enclosure url="https://example.com/__VERSION__/dozycat6-5.delta" sparkle:deltaFrom="5"/>
</item>
<item>
<sparkle:shortVersionString>0.1.4</sparkle:shortVersionString>
<enclosure url="https://example.com/__VERSION__/dozycat-0.1.4-arm64.dmg" sparkle:edSignature="old-fixture"/>
</item>
</channel></rss>
'''


class AppcastTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.project = self.root / 'apps/desktop/pet-mac'
        (self.project / 'scripts').mkdir(parents=True)
        (self.project / 'dist').mkdir()
        shutil.copy(SCRIPT, self.project / 'scripts/make-appcast.sh')
        self.site = self.root / 'site'
        self.site.mkdir()
        (self.site / 'appcast.xml').write_text('existing feed')
        (self.site / 'index.html').write_text('releases/latest/download/dozycat-0.1.5-arm64.dmg')
        self.fixture = self.root / 'fixture.xml'
        self.fixture.write_text(FEED)
        self.tool = self.project / 'build/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_appcast'
        self.tool.parent.mkdir(parents=True)
        self.tool.write_text('#!/bin/bash\ncp "$FIXTURE" "$4"\n')
        self.tool.chmod(0o755)
        self.env = dict(os.environ, HOME=str(self.root / 'empty-home'), FIXTURE=str(self.fixture))
        self.env.pop('DOZYCAT_GENERATE_APPCAST', None)
        self.env.pop('DOZYCAT_DL_PREFIX', None)

    def run_script(self):
        return subprocess.run(['bash', str(self.project / 'scripts/make-appcast.sh')],
                              env=self.env, capture_output=True, text=True)

    def assert_preserved(self):
        self.assertEqual((self.site / 'appcast.xml').read_text(), 'existing feed')
        self.assertEqual(list(self.site.glob('.appcast.*')), [])

    def test_new_machine_cache_and_historical_tags(self):
        result = self.run_script()
        self.assertEqual(result.returncode, 0, result.stderr)
        feed = (self.site / 'appcast.xml').read_text()
        self.assertIn('/download/0.1.5/dozycat-0.1.5-arm64.dmg', feed)
        self.assertIn('/download/0.1.5/dozycat6-5.delta', feed)
        self.assertIn('/download/0.1.4/dozycat-0.1.4-arm64.dmg', feed)
        self.assertNotIn('__VERSION__', feed)
        self.assertIn('sparkle:edSignature="fixture"', feed)

    def test_stale_download_does_not_overwrite_feed(self):
        (self.site / 'index.html').write_text('releases/latest/download/dozycat-0.1.4-arm64.dmg')
        self.assertNotEqual(self.run_script().returncode, 0)
        self.assert_preserved()

    def test_generator_failure_does_not_overwrite_feed(self):
        self.tool.write_text('#!/bin/bash\necho partial > "$4"\nexit 1\n')
        self.assertNotEqual(self.run_script().returncode, 0)
        self.assert_preserved()

    def test_missing_cache_reports_action(self):
        shutil.rmtree(self.project / 'build')
        result = self.run_script()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('generate_appcast not found', result.stderr)
        self.assert_preserved()

    def test_wrong_archive_version_is_rejected(self):
        self.fixture.write_text(FEED.replace('dozycat-0.1.5-arm64', 'dozycat-0.1.3-arm64'))
        self.assertNotEqual(self.run_script().returncode, 0)
        self.assert_preserved()


if __name__ == '__main__':
    unittest.main()
