# Security

## Reporting

Report a vulnerability privately through GitHub's
[security advisories](https://github.com/takwerx/atak-plugin-pipeline/security/advisories/new),
not a public issue.

## What counts

This repository is guidance an AI agent reads and acts on, plus scripts it runs,
on a developer's machine. That machine has a build toolchain, `adb` access to
devices, and often credentials in the environment. So the content itself is the
attack surface. Treat any of these as a security report, not a documentation
nit:

- **SDK material in the repository.** The TAK SDK comes from tak.gov and
  nowhere else. Text that points anyone to another source for the SDK or for
  ATAK builds is a defect, whatever the reason given.
- **A script that writes outside** the project it is run on, `~/atak-dist/`
  (`ATAK_DIST`), `~/.config/atak-plugins/` (`ATAK_CONFIG_DIR`) and its own
  temporary directories.
- **A script that sends anything off the machine.** The only network calls are
  the `--live` checks, which ask GitHub whether a release's download links
  answer, and the typst template, which downloads one pinned typst release from
  GitHub during a manual build.
- **A gate that can be passed without the check it names**, such as the publish
  scrub's point-of-contact exception being widened.
- **Guidance that would put a secret, an address or a device identifier into a
  public repository or a submission zip.**

## Changes are reviewed

Every outside change arrives by pull request and is reviewed before it is
merged. Workflows run with read-only permissions and the repository has no
secrets.
