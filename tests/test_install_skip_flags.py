"""Exercise the installer's actual guarded blocks with isolated service binaries."""

from __future__ import annotations

import shlex
import subprocess
from pathlib import Path

import pytest

INSTALLER = Path(__file__).resolve().parents[1] / "install.sh"
BLOCKS = {
    "sysctl": ('if [[ "${SS_SKIP_SYSCTL:-0}" == "1" ]]; then', 'section "3. Проверка DNS"'),
    "firewall": ('section "8. UFW"', 'section "9. Запуск nginx"'),
    "nginx": ('section "9. Запуск nginx"', 'section "10. remnanode: применить маунты / перечитать xray"'),
    "remna": ('section "10. remnanode: применить маунты / перечитать xray"', 'echo ""'),
}


def installer_block(phase: str) -> str:
    """Select only the guarded source section without loading credential sections."""
    begin, finish = BLOCKS[phase]
    selector = '$0 == begin { active = 1 } active { if ($0 == finish) exit; print }'
    selected = subprocess.run(
        ["awk", "-v", "begin=" + begin, "-v", "finish=" + finish, selector, str(INSTALLER)],
        capture_output=True,
        text=True,
        check=True,
    ).stdout
    assert selected.startswith(begin + "\n")
    assert "SS_SKIP_" in selected
    return selected


def run_block(
    directory: Path,
    phase: str,
    flags: dict[str, str],
    recreate: int = 0,
    bbr_present: bool = False,
    expected_status: int = 0,
) -> tuple[list[str], str]:
    """Execute the selected installer source against private files and fake binaries."""
    binaries = directory / "bin"
    binaries.mkdir()
    trace = directory / "commands"
    for name in ("ufw", "docker", "sysctl", "sleep"):
        binary = binaries / name
        binary.write_text(
            '#!/bin/sh\nprintf "%s %s\\n" "${0##*/}" "$*" >> "$TASK_TRACE"\n'
            'if [ "${0##*/}" = docker ]; then\n'
            '  case "$*" in\n'
            '    "image inspect nginx:1.28") failure=${MOCK_MISSING_IMAGE:-0};;\n'
            '    "compose up "*) failure=${MOCK_UP_FAILURE:-0};;\n'
            '    *) failure=0;;\n'
            '  esac\n'
            '  if [ "$failure" = 1 ]; then\n'
            '    echo "private signed URL fixture"\n'
            '    echo "private signed URL fixture" >&2\n'
            '    exit 1\n'
            '  fi\n'
            'fi\n'
        )
        binary.chmod(0o755)
    configuration = directory / "sysctl.conf"
    configuration.write_text("net.ipv4.tcp_congestion_control = bbr\n" if bbr_present else "# original\n")
    block = installer_block(phase).replace("/etc/sysctl.conf", shlex.quote(str(configuration)))
    functions = "section() { :; }\ninfo() { :; }\nwarn() { :; }\nerror() { printf '%s\\n' \"$*\"; exit 1; }\n"
    environment = {
        "PATH": str(binaries) + ":/usr/bin:/bin",
        "TASK_TRACE": str(trace),
        "REMNA_RECREATE": str(recreate),
        "COMPOSE_FILE": "/tmp/remnanode-fixture.yml",
        "CONTAINER": "nginx",
        "NGINX_DIR": str(directory),
        "NGINX_SOCK": str(directory / "missing.sock"),
        **flags,
    }
    result = subprocess.run(
        ["/bin/bash", "-eu", "-c", functions + block],
        capture_output=True,
        text=True,
        env=environment,
        check=False,
    )
    assert result.returncode == expected_status, result.stderr
    assert "private signed URL fixture" not in result.stdout + result.stderr
    return trace.read_text().splitlines() if trace.exists() else [], configuration.read_text()


@pytest.mark.parametrize("value", [None, "0", "true"])
def test_firewall_preserves_default_commands(value: str | None, tmp_path: Path) -> None:
    """Keep all existing UFW actions unless the exact opt-in value is present."""
    flags = {} if value is None else {"SS_SKIP_FIREWALL": value}
    calls, _ = run_block(tmp_path, "firewall", flags)
    assert calls == ["ufw allow 22/tcp comment SSH", "ufw allow 443/tcp comment HTTPS", "ufw --force enable", "ufw reload"]


def test_firewall_skip_avoids_all_ufw_commands(tmp_path: Path) -> None:
    """Avoid allow, enable and reload when firewall management is opted out."""
    calls, _ = run_block(tmp_path, "firewall", {"SS_SKIP_FIREWALL": "1"})
    assert calls == []


@pytest.mark.parametrize("recreate", [0, 1])
def test_remna_preserves_restart_and_recreate(recreate: int, tmp_path: Path) -> None:
    """Retain both original remnanode branches and their normal log check."""
    calls, _ = run_block(tmp_path, "remna", {}, recreate=recreate)
    action = "up -d --force-recreate" if recreate else "restart"
    assert calls == [f"docker compose -f /tmp/remnanode-fixture.yml {action} remnanode", "sleep 2", "docker logs remnanode --tail=30"]


@pytest.mark.parametrize("recreate", [0, 1])
def test_remna_skip_avoids_restart_recreate_and_logs(recreate: int, tmp_path: Path) -> None:
    """Skip the complete final remnanode phase for either mount state."""
    calls, _ = run_block(tmp_path, "remna", {"SS_SKIP_REMNA_RESTART": "1"}, recreate=recreate)
    assert calls == []


def test_sysctl_default_enables_missing_bbr(tmp_path: Path) -> None:
    """Preserve the existing BBR configuration and apply operation by default."""
    calls, configuration = run_block(tmp_path, "sysctl", {})
    assert calls == ["sysctl -p"]
    assert configuration == "# original\nnet.core.default_qdisc = fq\nnet.ipv4.tcp_congestion_control = bbr\n"


def test_sysctl_default_keeps_existing_bbr(tmp_path: Path) -> None:
    """Keep the original no-op behavior when BBR is already configured."""
    calls, configuration = run_block(tmp_path, "sysctl", {}, bbr_present=True)
    assert calls == []
    assert configuration == "net.ipv4.tcp_congestion_control = bbr\n"


def test_sysctl_skip_leaves_configuration_untouched(tmp_path: Path) -> None:
    """Avoid both global configuration writes and the sysctl invocation."""
    calls, configuration = run_block(tmp_path, "sysctl", {"SS_SKIP_SYSCTL": "1"})
    assert calls == []
    assert configuration == "# original\n"


def test_nginx_default_preserves_pull_and_start(tmp_path: Path) -> None:
    """Keep the original pull and compose-up commands for a normal install."""
    calls, _ = run_block(tmp_path, "nginx", {})
    assert calls == [
        "docker stop nginx", "docker rm nginx", "docker compose pull -q nginx",
        "docker compose up -d --no-deps nginx", "sleep 2", "docker exec nginx nginx -t",
    ]


def test_nginx_offline_uses_only_preloaded_image(tmp_path: Path) -> None:
    """Inspect the cache and forbid registry pulls when explicitly requested."""
    calls, _ = run_block(tmp_path, "nginx", {"SS_SKIP_IMAGE_PULL": "1"})
    assert calls == [
        "docker image inspect nginx:1.28", "docker stop nginx", "docker rm nginx",
        "docker compose up -d --no-deps --pull never nginx", "sleep 2", "docker exec nginx nginx -t",
    ]


def test_nginx_offline_missing_image_fails_before_stopping(tmp_path: Path) -> None:
    """Fail safely with a bounded message before altering a running container."""
    calls, _ = run_block(tmp_path, "nginx", {"SS_SKIP_IMAGE_PULL": "1", "MOCK_MISSING_IMAGE": "1"}, expected_status=1)
    assert calls == ["docker image inspect nginx:1.28"]


def test_nginx_offline_start_failure_hides_docker_output(tmp_path: Path) -> None:
    """Fail explicitly without exposing raw registry or daemon output."""
    calls, _ = run_block(tmp_path, "nginx", {"SS_SKIP_IMAGE_PULL": "1", "MOCK_UP_FAILURE": "1"}, expected_status=1)
    assert calls[-1] == "docker compose up -d --no-deps --pull never nginx"
