"""The Google Assistant SDK Custom integration."""
from __future__ import annotations

import logging
import os
import subprocess

import homeassistant.components.google_assistant_sdk as google_assistant_sdk
from homeassistant.config_entries import ConfigEntry
from homeassistant.core import HomeAssistant, callback
from homeassistant.helpers.start import async_at_start

_LOGGER = logging.getLogger(__name__)
PATCH_FILE = os.path.dirname(os.path.realpath(__file__)) + "/google_assistant_sdk.patch"
CWD = os.path.dirname(os.path.realpath(google_assistant_sdk.__file__))
GIT_APPLY_CMD = "git apply -p4"


async def async_setup_entry(hass: HomeAssistant, entry: ConfigEntry) -> bool:
    """Set up Google Assistant SDK Custom from a config entry."""

    if run_command(f"{GIT_APPLY_CMD} --reverse --check {PATCH_FILE}", should_log_error=False):
        _LOGGER.info("Already patched, enjoy :)")
        return True

    _LOGGER.info("Applying patch")
    if not run_command(f"{GIT_APPLY_CMD} -- {PATCH_FILE}"):
        _LOGGER.error("Failed to apply patch :(")
        return False

    _LOGGER.info("Patched, enjoy :)")
    _LOGGER.info("Restart Home Assistant to use the patch")
    return True


async def async_unload_entry(hass: HomeAssistant, entry: ConfigEntry) -> bool:
    """Unload a config entry."""
    _LOGGER.info("Reversing patch")
    if run_command(f"{GIT_APPLY_CMD} --reverse {PATCH_FILE}"):
        _LOGGER.info("Reversed patch")
    else:
        _LOGGER.warning("Failed to reverse patch")
    return True


def run_command(cmd: str, should_log_error: bool = True) -> bool:
    """Call subprocess.run. Returns true iff successful."""
    _LOGGER.debug("Running: %s", cmd)
    ret = subprocess.run(cmd, shell=True, capture_output=True, check=False, cwd=CWD)
    if ret.returncode and should_log_error:
        _LOGGER.error(
            "Error running command: %s - stderr:%s, stdout:%s",
            cmd,
            ret.stderr,
            ret.stdout,
        )
    return not ret.returncode
