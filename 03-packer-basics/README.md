# Lesson 3: Packer basics with Docker

In the first two lessons, Terraform created infrastructure. In this lesson,
Packer creates an image.

This lesson uses Docker because it is quick and stays on your computer. It does
not create anything in GCP.

## What you will learn

- what a Packer template describes
- how a source becomes an image
- how provisioners change an image
- how variables change a build
- how post-processors name the finished images

## The simple mental model

~~~text
Ubuntu source image
        |
        v
temporary container
        |
        v
shell provisioners add and inspect files
        |
        v
saved Docker image with a useful tag
~~~

Packer controls this process. Docker creates the temporary container and stores
the final image.

## Files in this lesson

- `docker-ubuntu.pkr.hcl` is the Packer template.
- `example.auto.pkrvars.hcl` gives `docker_image` a local value automatically.

## Before you start

Install Packer and Docker, then make sure Docker Desktop is running.

~~~powershell
packer version
docker version
~~~

## Read the template

The template has five useful parts:

1. `required_plugins` tells Packer to install the Docker plugin.
2. `variable` lets us change an input without rewriting the template.
3. `source` describes the starting Docker image.
4. `build` joins the sources and provisioners together.
5. `post-processor` gives each finished image a clear Docker tag.

There are two sources so you can see that Packer can run independent builds in
parallel. The variable file selects Ubuntu 22.04 for one source. The other
source uses Ubuntu 24.04.

## Build the images

Run these commands from this lesson folder:

~~~powershell
cd "03-packer-basics"
packer init .
packer fmt .
packer validate .
packer build .
~~~

`packer init` downloads the plugin. `packer validate` checks the template.
`packer build` creates temporary containers, runs the shell commands inside
them, and saves the results as Docker images.

Look at the images:

~~~powershell
docker images learn-packer
~~~

Read the file that Packer added:

~~~powershell
docker run --rm learn-packer:configurable cat /example.txt
docker run --rm learn-packer:ubuntu-24-04 cat /example.txt
~~~

## Try a different variable

An `.auto.pkrvars.hcl` file is loaded automatically. You can also override it
on the command line:

~~~powershell
packer build -var "docker_image=ubuntu:24.04" .
~~~

Command-line values have a higher priority than automatically loaded variable
files.

## Pushing is a separate choice

This lesson only stores images locally. Pushing an image to Docker Hub needs a
Docker Hub account, a login, and a repository name. It is better to learn the
local build first.

## Clean up

Find the image IDs with `docker images learn-packer`, then remove the lesson
images when you no longer need them:

~~~powershell
docker image rm learn-packer:configurable learn-packer:ubuntu-24-04
~~~

## Remember

- Terraform creates infrastructure from an image.
- Packer creates the image itself.
- Provisioners run inside a temporary build environment.
- The finished image is the artifact.
- A local Packer build does not need a cloud account.

## Official documentation

- [Install Packer](https://developer.hashicorp.com/packer/install)
- [Packer Docker tutorial](https://developer.hashicorp.com/packer/tutorials/docker-get-started/docker-get-started-build-image)
- [Packer template syntax](https://developer.hashicorp.com/packer/docs/templates/hcl_templates)
- [Packer variables](https://developer.hashicorp.com/packer/docs/templates/hcl_templates/variables)
- [Docker builder](https://developer.hashicorp.com/packer/integrations/hashicorp/docker/latest/components/builder/docker)
- [Docker tag post-processor](https://developer.hashicorp.com/packer/integrations/hashicorp/docker/latest/components/post-processor/docker-tag)
