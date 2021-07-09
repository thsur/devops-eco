
# First time setup

## File system layout

Though there's no special layout required, the easiest approach would be to have two folders side by side, one holding this tool, this other one holding your projects:

```
$ cd dev # Change this to the root folder of your choice
$ mkdir ops
$ mkdir sites 
```

## Installation

First, make sure you have your SSH key registered with GitLabs. Afterwards, just fetch the repository. When done, you'll need to fetch some third party dependencies:

```
$ rm Gemfile.lock
$ bundle install
$ rake ansible:dependencies 
```

## SSH configuration

Make sure to have our standard SSH config file in place to be able to interact with our tree servers.  

# Configuration

The only file you need to care about is the config file found under `config/core.config.yml`. For a test run, just replace `remote_user` at the top of the file with your remote user name.

If you've changed the proposed file system layout, you'll also need to change this setting to reflect the folder your projects should live in:

```
base_dir: 
  root: "../sites" 
```

# Test run

## Initialize projects

To init all projects on tree07, which is the default, just do:

```
$ rake projects:init
```

Afterwards, have a look into your projects folder and explore the structure & contents of each initialized project. 

To initialize all projects from a different tree, just do:

```
$ rake projects:init -- tree05
```

This will either initialize all or just some of the projects from tree05, depending on each tree's `projects` setting in the core config file. 

## Fetch code base & db

Pick a project and change into its newly created folder. Have a look at what you can do from there by calling:

```
$ rake
```

First, let's fetch our code base and db:

```
$ rake fetch
$ rake fetch_db
```

## Init ddev

Before bringing your machine up, you'll first need to initialize it:

```
$ rake ddev:init
```

## Import db

To import your db, just do:

```
$ rake import_db
```

Most of the interaction between you & your VM happens via ddev, meaning you always have to change into `<your-src-dir>/.ddev` before running a [ddev command](https://ddev.readthedocs.io/en/stable/users/cli-usage/). 

## Bringing your machine up

```
$ rake ddev:start
```

# Disclaimer

This is very much a work in progress, so be careful & double check before doing anything potentially destructive.
