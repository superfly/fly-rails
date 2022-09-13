## Purpose

Add [Fly.io](https://fly.io) support to [Rails](https://rubyonrails.org/).

## Status

<u>pre-alpha</u>.

In fact, the gem has not been yet been pushed to the rubygems
repository as while creating a github repository is an easily reversible act,
wiping all memory of a mis-named gem is considerably more challenging.

It currently is possible to build the gem files, install the prerequisite
`ruby-fly` gem, and then install the platform specific gem using `--local`.
You can also add the gem to your Gemfile using the `path:` argument to the
`gem` statement/method call.  Of course, all of this will be taken care of
for you once this gem has been published.

## Quickstart/summary

```sh
rails new demo
cd demo
bundle add fly.io-rails
flyctl auth login
bin/rails fly:launch
bin/rails deploy
```

## Build instructions

```
rake package
```

This will involve downloading binaries from github and building gems for
every supported platform as well as an additional gem that doesn't
include a binary.

To download new binaries, run `rake clobber` then `rake package` agein.

## Description

 -  `bundle add fly.io-rails`
    
    This will install `ruby-fly` middleware, add new Rails tasks, extend the
    channel and job generatotors, and platform binaries for
    [flyctl](https://github.com/superfly/flyctl#readme).  I've followed the
    trail blazed by [nokogiri](https://nokogiri.org/) and others to make
    platform binaries happen.

 - `bin/rails fly:launch`

   This won't be a mere front enty to [`flyctl
   launch`](https://fly.io/docs/flyctl/launch/).  It will use
   [`thor`](https://github.com/rails/thor#thor) to rewrite the configuration
   for the `production` environment as well as tweak the `Dockerfile` and
   `fly.toml` based on your application - in particular the configuration for
   ActiveRecord, ActiveJob, and ActionCable.  The people at Fly will know what
   databases and message queing systems work best on their platform and should
   make it easy to do the right thing.

   As an example, the default production database for a new application in
   Rails is sqlite3.  Either this will need to be replaced by Postgre in
   the Rails configuration *or* a volume will need to be defined, mounted,
   and the Rails configuration modified to point to the new mount point.

   This gem should pick one of those paths as the default, and provide an option to chose other paths.

 - `bin/rails generate channel`, `bin/rails generate job`, etc.

   Rails applications are generally not invented fully formed.  They evolve and
   add features.  I don't want people to think about having to configure rails
   AND configure fly when then add features.  Generators that developers
   already use today should be able to update both the Rails and Fly
   configurations in a consistent manner.

For now, both the Rails tasks and generators don't actually modify the Rails
configuratio to support Fly, instead they merely output the string `Configuring
fly...`.  Let your imagination run wild.

## Motivation

Oversimplifying and exagerating to make a point, `flyctl launch` generates an
initial fly configuration based on the state of the application at launch time
but leaves configuring your Rails application up to you.  The initial Fly
configuration may need to be tweaked, and both the fly and Rails configurations
will need to be maintained as the application evolves.

From a Rails developer perspective, this makes fly an additional framework that
must be learned and attended to.

This can all be changed with a single `bundle add` command.  Everything from
new `rails` tasks to extending the behavior of existing generators to making
changes to configuration to monkeypatching Rails internals itself are on the
table.

A few sublte but important mindset changes are necessary to pull this off:

  * Instead of "we support every (or perhaps even only 'most') Rails
    configuration" the mindset we should strive for is "we provide a default
    production configuration that works for most, and provide options to add or
    replace components as desired".

    We should be bold and daring.  We should chose a default web server, a
    default database, a default active job queue adapter, a default action
    cable subscription adapter, etc., etc., etc.

    Over time, this should encompas everything needed for monitoring and
    deployment.  Requirements for things like log file management should be
    anticipated and accounted for.

  * Any configuration artifact that is generated and needs to be checked into
    the application's source control repository needs to be [beautiful
    code](https://rubyonrails.org/doctrine#beautiful-code).  If you look at
    configuration files provided by either `rails new` or by rails generators,
    they have comments.  They don't configure things that don't apply to you.

    A concrete example: Rails 7 applications default to import maps.  A
    `Dockerfile` generated for such an app should not contain code that deals
    with `yarn` or `node_modules`. 

And as a closing remark - to be fair adding Rails support to Fly and adding Fly
support to Rails are more complementary than competing efforts.  

## Future

> Que sera, sera

-- Doris Day

I don't know what the future is going to hold, but some guesses:

  * It is plausible that a code base written in Ruby and with access to
    libraries like [Thos](http://whatisthor.com/) and focused exclusively on
    Rails may attract more contributions from the Rails community than a
    codebase written in Go and targetting many disparate frameworks.
  * Flyctl launch can continue to provide a basic Fly configuration for Rails,
    but if this effort is successful these configurations would largely be
    replaced by more tailors configurations that are updated by generators and
    rake tasks as the application evolves.
  * Not every flyctl command needs to have a Rails wrapper -- only the common
    task do.  It is quiet OK for developers to deal directly with fly when it
    makes sence to do so.  But those flyctl command that are wrapped may need
    options added that enable them to be run without the need to prompt the
    user.
  * This gem could be built and published alongside the flyctl executables, and
    `flyctl version update` could detect whether or not it was installed as a
    gem and react appropriately.

## Call to Action

> good ideas and bad code build communities, the other three combinations do
> not

-- Stefano Mazzocchi

> the best way to get the right answer on the internet is not to ask a
> question; it's to post the wrong answer.

-- Ward Cunningham

I don't presume that any specific line of code in this initial implementation
will last the test of time.  Heck, I'm not even confident enough in the
proposed name to register the gem, though the name does feel *rails-like* -
just take a look at any Rails `Gemfile` to see.

My hope is that there is enough scaffolding here to not only make clear what
the possibilities are, but also enough structure so that it is fairly obvious
where new logic should go, together there is not only enough promise and
structure to attract a community.

Some starter ideas:

 * Can we make `bin/rails deploy` smart enough to invoke `flyctl auth login` if
   you are not logged in and `bin/rails fly:launch` if the application had not
   previously been launched, with the goal of reducing the number of commands a
   user has to issue to get started.  Also I'm impressed by the way auth login
   launches a browser, can we do the same for fly launch?

 * While a number of application configuration changes are made through
   generators, not all are.  For example, upgrading the version of Ruby to be
   used.  Perhaps we could create tasks for some of these, but likely it will
   be worthwhile to create a `fly:reconfig` task.

Finally, once this repository is in the superfly github organization and
a gem has been published, this README should be rewritten from focus on
raison d'être and to a focus on what value it would bring to those that
install and use it.
