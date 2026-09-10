"""Exercise release publication without touching real builds."""
import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import zipfile

spec = importlib.util.spec_from_file_location('packaging', Path(__file__).resolve().parents[1] / 'tools/package_builds.py')
p = importlib.util.module_from_spec(spec)
spec.loader.exec_module(p)

class PublicationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def release(self, version):
        release = self.root / version
        for platform, executable, _ in p.PLATFORMS:
            folder = release / platform
            folder.mkdir(parents=True)
            for name in (executable, 'APHELION.pck', 'README.md', 'THIRD_PARTY_NOTICES.md'):
                (folder / name).write_text(version)
        for name in p.PACKAGE_NAMES:
            with zipfile.ZipFile(release / name, 'w') as archive:
                archive.writestr('fixture', version)
        (release / 'SHA256SUMS.txt').write_text(''.join(f'{p.sha256(release / name)}  {name}\n' for name in p.PACKAGE_NAMES))
        return release

    def test_preserves_old_files_and_updates_idempotently(self):
        old = self.root / 'linux'
        old.mkdir()
        binary = old / 'APHELION.x86_64'
        binary.write_text('old running executable')
        inode = binary.stat().st_ino
        with binary.open() as running:
            release = self.release('0.1.2')
            p.publish_current(self.root, release, '0.1.2')
            self.assertEqual(running.read(), 'old running executable')
        archived = list((self.root / 'archive').glob('*/linux/APHELION.x86_64'))
        self.assertEqual(len(archived), 1)
        self.assertEqual(archived[0].stat().st_ino, inode)
        self.assertEqual(old.resolve(), release / 'linux')
        link_inode = old.lstat().st_ino
        p.publish_current(self.root, release, '0.1.2')
        self.assertEqual(old.lstat().st_ino, link_inode)
        newer = self.release('0.1.3')
        p.publish_current(self.root, newer, '0.1.3')
        self.assertEqual(old.resolve(), newer / 'linux')
        self.assertEqual((self.root / 'LATEST').read_text(), '0.1.3\n')

    def test_invalid_checksum_does_not_publish(self):
        release = self.release('0.1.2')
        (release / p.PACKAGE_NAMES[0]).write_bytes(b'broken')
        with self.assertRaises(ValueError):
            p.publish_current(self.root, release, '0.1.2')
        self.assertFalse((self.root / 'LATEST').exists())
        self.assertFalse((self.root / 'linux').exists())

    def test_copy_fallback(self):
        release = self.release('0.1.2')
        p.publish_current(self.root, release, '0.1.2', use_symlinks=False)
        self.assertFalse((self.root / 'linux').is_symlink())
        inode = (self.root / 'linux').stat().st_ino
        p.publish_current(self.root, release, '0.1.2', use_symlinks=False)
        self.assertEqual((self.root / 'linux').stat().st_ino, inode)

    def test_failed_publication_restores_previous_release(self):
        first = self.release('0.1.2')
        p.publish_current(self.root, first, '0.1.2')
        second = self.release('0.1.3')
        original = Path.replace
        def fail_windows(path, target):
            if path.name == 'windows' and path.parent.name.startswith('.current-'):
                raise OSError('simulated locked destination')
            return original(path, target)
        with patch.object(Path, 'replace', fail_windows):
            with self.assertRaises(OSError):
                p.publish_current(self.root, second, '0.1.3')
        self.assertEqual((self.root / 'linux').resolve(), first / 'linux')
        self.assertEqual((self.root / 'LATEST').read_text(), '0.1.2\n')

if __name__ == '__main__':
    unittest.main()
