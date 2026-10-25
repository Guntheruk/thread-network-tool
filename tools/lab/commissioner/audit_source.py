"""Fail build unless the app's real Probe uses only the reviewed GET-only calls."""
from pathlib import Path
import re
import sys

source = Path(sys.argv[1]).read_text()
calls = re.findall(r"commissioner->([A-Za-z0-9_]+)\s*\(", source)
assert sorted(calls) == sorted(["Init", "Connect", "GetActiveDataset", "GetPendingDataset"])
assert "Petition(" not in source and "SetPendingDataset(" not in source
