"""Validate the course stack inside the running Kit application."""

from importlib.metadata import version
from pathlib import Path
import sys

import isaaclab
import omni.usd

lab_root = Path('/opt/isaaclab-course')
assert (lab_root / 'VERSION').read_text().strip() == '2.3.0'
assert str(Path(isaaclab.__file__).resolve()).startswith(str(lab_root))
assert Path('/isaac-sim/VERSION').read_text().startswith('5.1.0')
assert sys.version_info[:2] == (3, 11)
assert version('gymnasium') == '1.2.0'
assert version('starlette') == '0.45.3'
print(
    f'VLA_COURSE_RUNTIME_OK Sim=5.1.0 Lab=2.3.0 Python={sys.version.split()[0]} '
    f'isaaclab_package={version("isaaclab")} '
    f'stage_open={omni.usd.get_context().get_stage() is not None}',
    flush=True,
)
