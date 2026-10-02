<!-- SPDX-License-Identifier: MIT -->
<!-- Published to SudoEvan/cold-brew-up by cold-brew's publish-installer workflow.
     Edit it at cold-brew/config/installer/README.md, not in the public repo. -->

# cold-brew-up

The public bootstrap entry point for [cold-brew](https://github.com/SudoEvan/cold-brew),
a personal dev-environment setup. This repo exists only to serve `install.sh`
to a machine that has no credentials yet, because cold-brew itself is private.

## Install

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/SudoEvan/cold-brew-up/v1.0.0/install.sh)"
```

Use that form, not `curl … | bash`. Piping leaves stdin attached to the script,
so the browser logins have no terminal to read from and the run dies halfway.
The script detects that case and refuses rather than failing part-way.

Pin a tag rather than `main`: a `curl | bash` endpoint tracking a moving branch
means whoever compromises this repo owns every machine set up afterwards.

## Verify first

```bash
curl -fsSL -O https://raw.githubusercontent.com/SudoEvan/cold-brew-up/v1.0.0/install.sh
curl -fsSL https://raw.githubusercontent.com/SudoEvan/cold-brew-up/v1.0.0/install.sh.sha256
shasum -a 256 install.sh    # compare with the .sha256, then run it
bash install.sh
```

## What it does

Homebrew (which brings the Xcode Command Line Tools and a usable git with it)
→ `gh` → GitHub login → SSH key generated and uploaded → clone cold-brew →
`./bootstrap.sh` → GitLab and Gitea push auth.

Interaction needed: your password once for Homebrew, a GitHub browser login, a
GitLab browser login, and one paste of the printed SSH key into Gitea, which
has no CLI to upload it. Everything else is unattended.

Options:

```bash
./install.sh --no-bootstrap        # set up auth and clone, stop before bootstrap
./install.sh --repo-dir ~/src/cb   # clone somewhere other than the default
```

## Afterwards

```bash
cd ~/Developer/repos/cold-brew
make doctor          # assert the machine is in the expected state
make help            # every available target
```

## Do not send changes here

This repo is generated. `install.sh` is mirrored one-way from cold-brew on every
change, so edits here are overwritten. Open issues or changes against cold-brew.
