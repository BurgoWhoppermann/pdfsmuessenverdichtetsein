# -*- mode: python ; coding: utf-8 -*-
"""PyInstaller build spec for PDF Compressor."""

import sys
from pathlib import Path

block_cipher = None

# Get the project root
project_root = Path(SPECPATH)

a = Analysis(
    [str(project_root / 'src' / 'main.py')],
    pathex=[str(project_root / 'src')],
    binaries=[],
    datas=[
        # Include assets if they exist
        (str(project_root / 'assets'), 'assets'),
        (str(project_root / 'image.png'), '.'),
    ],
    hiddenimports=[
        'PIL._tkinter_finder',
        'customtkinter',
        'tkinterdnd2',
        'fitz',
    ],
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=[],
    win_no_prefer_redirects=False,
    win_private_assemblies=False,
    cipher=block_cipher,
    noarchive=False,
)

pyz = PYZ(a.pure, a.zipped_data, cipher=block_cipher)

exe = EXE(
    pyz,
    a.scripts,
    [],
    exclude_binaries=True,
    name='PDFs muessen verdichtet sein',
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=True,
    console=False,
    disable_windowed_traceback=False,
    argv_emulation=True,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
)

coll = COLLECT(
    exe,
    a.binaries,
    a.zipfiles,
    a.datas,
    strip=False,
    upx=True,
    upx_exclude=[],
    name='PDFs muessen verdichtet sein',
)

app = BUNDLE(
    coll,
    name='PDFs muessen verdichtet sein.app',
    icon=str(project_root / 'assets' / 'icon.icns') if (project_root / 'assets' / 'icon.icns').exists() else None,
    bundle_identifier='com.pdfcompressor.app',
    info_plist={
        'CFBundleName': 'PDFs muessen verdichtet sein',
        'CFBundleDisplayName': 'PDFs müssen verdichtet sein',
        'CFBundleVersion': '1.0.0',
        'CFBundleShortVersionString': '1.0.0',
        'NSHighResolutionCapable': True,
        'NSRequiresAquaSystemAppearance': False,
        'CFBundleDocumentTypes': [
            {
                'CFBundleTypeName': 'PDF Document',
                'CFBundleTypeRole': 'Editor',
                'LSHandlerRank': 'Alternate',
                'LSItemContentTypes': ['com.adobe.pdf'],
            }
        ],
    },
)
