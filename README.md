# tmkbd

A utility for managing [Termux](https://termux.dev/) keyboard layouts.


## Installation

```sh
mv tmkbd.sh tmkbd          # remove file extension
termux-fix-shebang tmkbd   # update hashbang
chmod u+x tmkbd            # make it an executable
# NOTE: You can customize install location using TMKBD_INSTALL env variable
./tmkbd                    # run setup
```

Finally, place `tmkbd` somewhere in your `PATH`.


## How it works

This script creates a directory (`~/.local/share/tmkbd` by default).
The contents look like this:

```
~ $ exa -T ~/.local/share/tmkbd
/home/user/.local/share/tmkbd
├── base.properties
├── keyboards
│  └── profile.json
└── profiles
   └── profile.properties
```

- `base.properties` are properties extracted from `termux.properties` files -
   everything except for `extra-keys`
- `keyboards/` contains raw JSON files just as you have provided them.
- `profiles/` contains compiled `termux.properties` files
   (`base.properties` + compiled keyboard layout in `extra-keys`)

During the installation, your old `termux.profile` gets replaced with a symlink
to `base.properties`. If you set a custom layout (with `tmkbd use` or `tmkbd cycle`)
the symlink get updated to appropriate profile in `profiles` directory.

Your `termux.profile` will look something like this:

```
~ $ exa -l ~/.termux
lrwxrwxrwx 49 user 20 Jul 19:01 termux.properties -> /home/user/.local/share/tmkbd/base.properties
```


# About this repo

Currently this repository only contains `tmkbd`. If I write more Termux scripts
all of them will be available here.
