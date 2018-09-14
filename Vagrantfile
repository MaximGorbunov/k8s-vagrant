%w(vagrant-hostmanager).each do | plugin |
  unless Vagrant.has_plugin?(plugin)
    system("vagrant plugin install #{plugin}", :chdir=>"/tmp") || exit!
  end
end
require 'yaml' 
vagrantRoot = File.dirname(__FILE__)
unless Pathname(vagrantRoot + '/k8s-cluster.yml').exist?
  fail "cluster config file k8s-cluster.yml not found"
end
servers = YAML.load_file(vagrantRoot + '/k8s-cluster.yml') 
key = File.readlines("#{Dir.home}/.ssh/id_rsa.pub").first.strip 
Vagrant.configure("2") do |config| 
    config.hostmanager.enabled = true 
    config.hostmanager.manage_host = true 
    servers.each do |server| 
        config.vm.define server["name"] do |machine| 
            machine.vm.synced_folder '.', '/vagrant', disabled: true
            machine.vm.box = server["box"] 
            machine.vm.hostname = server["name"] 
            machine.vm.network "private_network", ip: server["ip"] 
            machine.vm.provider "virtualbox" do |vb| 
                vb.name = server["name"] 
                vb.memory = server["mem"] 
                vb.cpus = server["cpu"] 
            end 
        end 
    end 
end
def isMasterNode(name)
  name.include? "master"
end