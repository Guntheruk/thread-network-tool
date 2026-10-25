#!/usr/bin/env python3
"""Resolve verified generated source, preparing a separate copy of a clean pin."""
from pathlib import Path
import argparse
import json
try:
    from . import prepare_commissioner_source as source_tools
except ImportError:
    import prepare_commissioner_source as source_tools


def resolve(source: Path, output: Path) -> Path:
    source = source.resolve()
    if (source / 'tnt-source-provenance.json').is_file():
        source_tools.verify_prepared(source)
        return source
    # Reuse a verified generation only after checking the supplied original is
    # still the exact clean parent and recursive pins. Never change that input.
    manifest = json.loads(source_tools.MANIFEST.read_text())
    source_tools.source_repositories(source, manifest)
    if output.exists() or output.is_symlink():
        source_tools.verify_prepared(output)
    else:
        source_tools.prepare(source, output)
    return output.resolve()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    print(resolve(args.source, args.output))


if __name__ == '__main__':
    main()
