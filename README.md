## Purpose

Add [Fly.io](https://fly.io) support to [Rails](https://rubyonrails.org/).

## Status

<u>pre-alpha</u>.

For usage instructions, see [Fly.io Rails Advanced Guide: Terraform](https://fly.io/docs/rails/advanced-guides/terraform/).

## Build instructions

```
rake package
```

This will involve downloading binaries from github and building gems for
every supported platform as well as an additional gem that doesn't
include a binary.

To download new binaries, run `rake clobber` then `rake package` agein.
