# Contributing

Findings, corrections and fixes are welcome, by issue or pull request.

## The one rule: every claim was seen happen

This skill is loaded into an agent's context and acted on. One invented claim
makes every other line in it harder to trust, so each rule here exists because
something shipped broken, and says what broke. Hold contributions to the same
standard:

- **Say how you know.** ATAK version, official build or the SDK's developer
  build, physical device or emulator, and the command, log line or `aapt` output
  that showed it. Put that in the PR description and the commit message, so the
  history keeps it after the text is reworded.
- **Say where it holds.** A fact seen on 5.8 only is written as 5.8 only. A fact
  seen once is not written as "always".
- **A claim you could not fully verify** is still worth sending. Label it
  `unverified` and say what is missing.

## What a pull request can be

- **A finding**: something new, with how you measured it.
- **A correction**: something here is wrong, with the evidence.
- **Stale**: something here no longer holds on a newer ATAK. Propose deleting
  it, or qualifying it with the versions it still applies to.
- **A script fix**: a gate that misses a case, or fails one it should pass.
  Include the input that shows it.
- **Structure**: moving or tightening text without adding claims.

One finding per pull request, so a weak one does not ride in with a strong one.

## What will be declined

- Anything from the TAK SDK: code, resources, Gradle scripts, binaries. The
  SDK's license forbids redistributing it. See [NOTICE.md](NOTICE.md).
- Anything learned by decompiling or reverse engineering ATAK.
- Advice nobody has run.
- Text that makes `SKILL.md` longer without making a plugin less likely to ship
  broken. Detail goes in `references/`.
- Anything specific to one organization's servers, catalog or fleet. The skill
  has to work for whoever clones it.

## Checks

CI runs on every pull request: `shellcheck` on `scripts/` and `hooks/`, the
`SKILL.md` frontmatter and length, every relative link in the Markdown, and a
refusal of binaries and SDK file names. Run shellcheck locally before you push:

```bash
shellcheck -S warning scripts/*.sh hooks/*.sh
```

## License

By contributing, you agree that your contribution is licensed under the
[MIT license](LICENSE) and that you have the right to submit it.
