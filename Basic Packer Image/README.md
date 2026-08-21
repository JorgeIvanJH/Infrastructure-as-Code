Official [Packer documentation](https://developer.hashicorp.com/packer/docs)

The real utility of Packer comes from automated provisioning in order to install and configure software in the machines prior to turning them into images.

Context: Packer creates images that are used to easily run VMs. These images are created with plugins that take packer code and translate to the provider chosen. Think of a plugin like a box containing everything needed to run up an image with software included, so a plugin contains builders and communicators. Builders is the component in a plugin that know how to create a temporary image and create an image out of it, while communicators are the mechanism used to upload files, execute scripts, etc in the machine being created.



# My first PAcker experience using [this guide](https://developer.hashicorp.com/packer/tutorials/docker-get-started/docker-get-started-build-image), and [this one](https://developer.hashicorp.com/packer/tutorials/docker-get-started/docker-get-started-provision), and [this one](https://developer.hashicorp.com/packer/tutorials/docker-get-started/docker-get-started-variables), and [this one](https://developer.hashicorp.com/packer/tutorials/docker-get-started/docker-get-started-parallel-builds), and [this one](https://developer.hashicorp.com/packer/tutorials/docker-get-started/docker-get-started-post-processors)

here we create a first image using packer and then a docker container.


## Packer template

A Packer template is a configuration file that defines the image you want to build and how to build it. 

This is a [packer template](packer_tutorial/docker-ubuntu.pkr.hcl)

### Packer Block

The *packer {} block* contains Packer settings.

    - The *required_plugins* block in the *Packer block* specifies all the plugins required by the template to build your image.

        - Each plugin block contains a version and source attribute. Packer will use these attributes to download the appropriate plugin(s).

            - The source attribute is only necessary when requiring a plugin outside the HashiCorp domain.

                - Plugins have builders. A builder is the component in a plugin that knows how to create machines and generate images from those machines. find all plugins [here](https://developer.hashicorp.com/packer/docs/builders)

### Source block

The *source block* configures a specific builder plugin, which is then invoked by a *build block*.

*Source blocks* use **builders** and **communicators** to define what kind of virtualization to use, how to launch the image you want to provision, and how to connect to it.

Builders and communicators are bundled together and configured side-by-side in a source block

A source block has two important labels: a *builder type* and a *name*. In our [example](packer_tutorial/docker-ubuntu.pkr.hcl) the builder type is "docker" and name is "ubuntu".

**Each builder has its own unique set of configuration attributes.** depending on the image being created. In the example template, the Docker builder configuration creates a new Docker image using ubuntu:jammy as the base image, then commits the container to an image.

    Note: The example template does not configure any *communicators*, because the Docker builder is a special case where Packer can't use a typical ssh or winrm connection.

### Build Block

The build block defines what packer should do with the VM after it is launched.

The Packer build block functions as an assembly line, where **sources** (above) act as the raw material (base OS/machine), **provisioners** perform the work (installing software/configurations), and **post-processors** package the finished artifact. This structure turns a generic source into a specialized image, allowing for automated creation, customization, and deployment of virtual machines or containers.


#### Add provisioner to template

Using provisioners allows you to completely automate modifications to your image. You can use shell scripts, file uploads, and integrations with modern configuration management tools such as Chef or Puppet.

in one fo the provisioners in our example we add a text file example.txt containing some message.

You can run as many provisioners as you'd like. Provisioners run in the order they are declared.

#### Add post-processor to template

While provisioners are run against an instance while it is running, post-processors run only after Packer saves the instance as an image.

In [our example](packer_tutorial/docker-ubuntu.pkr.hcl) we give names to the created images using *post-processor "docker-tag"* that tag the images after they have been created.

##### Sequential post-processing steps

**sequential "post-processor":** You may add as many post-processors as you want using the post-processor syntax, but each one will start from the original artifact output by the builder, **not the artifact created by a previously declared post-processor**.

**pipelines with "post-processors":** Use the post-processors (note the pluralization) block to create post-processing pipelines where the output of one post-processor becomes the input to another post-processor.

e.g: this would tag your image then push it to Docker Hub.

```json
  post-processors {
    post-processor "docker-tag" {
      repository = "jorgejaramilloherrera98795/packertesting"
      tags       = ["0.7"]
    }
    post-processor "docker-push" {}
  }
```

### Variables

You can use input variables to serve as parameters for a Packer build, allowing aspects of the build to be customized without altering Packer template. In addition, Packer variables are useful when you want to reference a specific value throughout your template.

Treat Packer variables as constants — you cannot update them during run time.

Find all ways to assign variables [here](https://developer.hashicorp.com/packer/guides/hcl/variables#assigning-variables). The order of ascending precedence is: variable defaults, environment variables, variable file(s), command-line flag

#### Build image with variable file

See [this file](Basic Packer Image\packer_tutorial\example.auto.pkrvars.hcl), it has the variable value assigned to it. And ust because its variable name (docker_image) is the same as defined in [the packer template](packer_tutorial/docker-ubuntu.pkr.hcl) (variable "docker_image") that value is assigned :

```bash
packer build .
```
you can override variable values like this:

```bash
packer build --var docker_image=ubuntu:focal .
```

### Parallel builds

 Packer can create multiple images in parallel, all configured from a single template. For example, Packer can build an Amazon AMI and a VMware virtual machine in parallel provisioned with the same scripts, resulting in near-identical images.

To use parallel builds, create a source then add the source to the sources array in the build block. Your sources do not need to be the same type. 

### Initialize Packer configuration

Initialize your Packer configuration with

```bash
packer init .
```

Packer will download the plugin you've defined above

### Format and validate your Packer template


```bash
packer fmt .
```

```bash
packer validate .
```

### Build Packer image

```bash
packer build docker-ubuntu.pkr.hcl
```

then you do whatever you need with the image (docker images, docker rmi IMAGE_ID, etc)


