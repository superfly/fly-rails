## Purpose

Add [Fly.io](https://fly.io) support to [Rails](https://rubyonrails.org/).

## Status

<u>alpha</u>.

For usage instructions, see the following guides:

  * [Machine API](https://fly.io/docs/rails/advanced-guides/machine/)
  * [Lite FS](https://fly.io/docs/rails/advanced-guides/litefs/)
  * [Terraform](https://fly.io/docs/rails/advanced-guides/terraform/)

## Key files:

  * Entrypoints: [lib/tasks/fly.rake](./lib/tasks/fly.rake), [lib/generators/app_generator.rb](./lib/generators/app_generator.rb), [lib/generators/terraform_generator.rb](.lib/generators/terraform_generator.rb) contain the deploy task, fly:app generator and
  fly:terraform generator respectively.
  * [lib/fly.io-rails/actions.rb](./lib/fly.io-rails/actions.rb) contains thor actions used by the
  rake task and generators.  Does some funky stuff to allow thor actions to
  be called from Rake.
  * [lib/fly.io-rails/machines.rb](./lib/fly.io-rails/machines.rb) wraps Fly.io's machine API as a Ruby module.
  * [lib/generators/templates](./lib/generators/templates) contains erb
  templates for all of the files produced primarily by the generator, but also
  by the deploy task.
  * [Rakefile](./Rakefile) used to build gems.  Includes native binaries for each supported platform.



## Build instructions

```
rake package
```

This will involve downloading binaries from github and building gems for
every supported platform as well as an additional gem that doesn't
include a binary.

To download new binaries, run `rake clobber` then `rake package` agein.

## Debugging instructions

This gem provides a Railtie, with rake tasks and a generator that uses
Thor and templates.  Being in Ruby, there is no "compile" step.  That
coupled with Bundler "local overrides" makes testing a breeze.  And
Rails 7 applications without node dependencies are quick to create.

A script like the following will destroy previous fly applications,
create a new rails app, add and then override this gem, and finally
copy in any files that would need to be manually edited.

```
if [ -e welcome/fly.toml ]; then
  app=$(awk -e '/^app\s+=/ { print $3 }' welcome/fly.toml | sed 's/"//g')
  fly apps destroy -y $app
fi
rm -rf welcome
rails new welcome
cd welcome
bundle config disable_local_branch_check true
bundle config set --local local.fly.io-rails /Users/rubys/git/fly.io-rails
bundle add fly.io-rails --git https://github.com/rubys/fly.io-rails.git
cp ../routes.rb config
# bin/rails generate terraform
# fly secrets set FLY_API_TOKEN=$(fly auth token)
# bin/rails generate controller job start complete status
# bin/rails generate job machine
# cp ../job_controller.rb app/controllers/
# cp ../machine_job.rb app/jobs/
```

Once created, I rerun using:

```
cd ..; sh redo-welcome; cd welcome; 
```

Generally after the finaly semicolon, I have commands like
`bin/rails generate fly:app --litefs; fly deploy`.  Rerunning
after I make a change is a matter of pushing the up arrow until
I find this command and then pressing enter.

