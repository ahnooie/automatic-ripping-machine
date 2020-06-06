# -*- mode: ruby -*-
# vi: set ft=ruby :

# All Vagrant configuration is done below. The "2" in Vagrant.configure
# configures the configuration version (we support older styles for
# backwards compatibility). Please don't change it unless you know what
# you're doing.
Vagrant.configure(2) do |config|
  # The most common configuration options are documented and commented below.
  # For a complete reference, please see the online documentation at
  # https://docs.vagrantup.com.

  # Every Vagrant development environment requires a box. You can search for
  # boxes at https://atlas.hashicorp.com/search.
  config.vm.box = "hashicorp/bionic64"

  # Provider-specific configuration so you can fine-tune various
  # backing providers for Vagrant. These expose provider-specific options.
  config.vm.provider "virtualbox" do |vb|
    # Display the VirtualBox GUI when booting the machine
    # vb.gui = true

    # Customize the amount of memory on the VM:
    vb.memory = "1024"
  end

  # Run Ansible from the Vagrant VM
  $inline_script = <<-INLINE_SCRIPT
    sudo apt-get install -y ansible
    cd /vagrant
    if [ ! -f config ]; then cp config{.sample,}; fi
    config_vars=$(env -i bash -c "set -a; . ./config; env" | sed 's/^\([^=]*\)=\(.*\)/\1="\2"/' | tr '\n' ' ')
    ansible-galaxy install jswetzen.automatic-ripping-machine
    ANSIBLE_FORCE_COLOR=true ansible-playbook -i="localhost," --extra-vars="$config_vars" -c local arm-ansible-playbook.yml
  INLINE_SCRIPT
  config.vm.provision "shell", inline: $inline_script, privileged: false, keep_color: true
end
