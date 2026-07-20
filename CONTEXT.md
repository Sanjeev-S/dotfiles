# Dotfiles

Cross-machine environment for one person's fleet — a personal laptop plus
always-on dev boxes, cloud and owned — kept reproducible by chezmoi.

## Language

**Machine type**:
The identity a box declares once at bootstrap (`mac-personal`, `mac-dev`,
`linux-dev`, `dgx-spark`) that drives every per-machine configuration
difference.
_Avoid_: machine profile, role, host type

**Dev box**:
An always-on machine used for remote interactive work: `linux-dev` (cloud,
Hetzner) and the owned hardware `mac-dev` (Mac mini) and `dgx-spark`.
Everything except the personal laptop.
_Avoid_: server, remote, agent box
