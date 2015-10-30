module Kontena
  module Models
    class ServicePod

      attr_reader :service_name, :instance_number, :deploy_rev, :labels,
                  :stateful, :image_name, :user, :cmd, :entrypoint, :memory,
                  :memory_swap, :cpu_shares, :privileged, :cap_add, :cap_drop,
                  :devices, :ports, :env, :volumes, :volumes_from, :net,
                  :log_driver, :log_opts

      # @param [Hash] attrs
      def initialize(attrs = {})
        @service_name = attrs['service_name']
        @instance_number = attrs['instance_number'] || 1
        @deploy_rev = attrs['deploy_rev']
        @labels = attrs['labels'] || {}
        @stateful = attrs['stateful'] || false
        @image_name = attrs['image_name']
        @user = attrs['user']
        @cmd = attrs['cmd']
        @entrypoint = attrs['entrypoint']
        @memory = attrs['memory']
        @memory_swap = attrs['memory_swap']
        @cpu_shares = attrs['cpu_shares']
        @privileged = attrs['privileged'] || false
        @cap_add = attrs['cap_add']
        @cap_drop = attrs['cap_drop']
        @devices = attrs['devices']
        @ports = attrs['ports']
        @env = attrs['env'] || []
        @volumes = attrs['volumes'] || []
        @volumes_from = attrs['volumes_from'] || []
        @net = attrs['net'] || 'bridge'
        @log_driver = attrs['log_driver']
        @log_opts = attrs['log_opts']
      end

      def overlay_network
        self.labels['io.kontena.container.overlay_cidr']
      end

      def can_expose_ports?
        !self.overlay_network.nil?
      end

      def stateless?
        !self.stateful
      end

      def stateful?
        !self.stateless?
      end

      def name
        "#{self.service_name}-#{self.instance_number}"
      end

      def data_volume_name
        "#{self.service_name}-#{self.instance_number}-volumes"
      end

      # @return [Hash]
      def service_config
        docker_opts = {
          'name' => self.name,
          'Image' => self.image_name,
          'HostName' => "#{self.name}.kontena.local"

        }
        docker_opts['User'] = self.user if self.user
        docker_opts['Cmd'] = self.cmd if self.cmd
        docker_opts['Entrypoint'] = self.entrypoint if self.entrypoint

        if self.can_expose_ports? && self.ports
          docker_opts['ExposedPorts'] = self.build_exposed_ports
        end
        if self.stateless? && self.volumes
          docker_opts['Volumes'] = self.build_volumes
        end

        labels = self.labels.dup
        labels['io.kontena.container.type'] = 'container'
        labels['io.kontena.container.name'] = self.name
        labels['io.kontena.container.pod'] = self.name
        labels['io.kontena.container.deploy_rev'] = self.deploy_rev
        labels['io.kontena.service.instance_number'] = self.instance_number.to_s
        docker_opts['Labels'] = labels
        docker_opts['HostConfig'] = self.service_host_config
        docker_opts
      end

      # @return [Hash]
      def service_host_config
        host_config = {
          'RestartPolicy' => {
            'Name' => 'always'
          }
        }
        bind_volumes = self.build_bind_volumes
        if bind_volumes.size > 0
          host_config['Binds'] = bind_volumes
        end
        if self.volumes_from.size > 0
          i = self.name.match(/^.+-(\d+)$/)[1]
          host_config['VolumesFrom'] = self.volumes_from.map{|v| v % [i] }
        end
        if self.can_expose_ports? && self.ports
          host_config['PortBindings'] = self.build_port_bindings
        end

        host_config['NetworkMode'] = self.net if self.net
        host_config['CpuShares'] = self.cpu_shares if self.cpu_shares
        host_config['Memory'] = self.memory if self.memory
        host_config['MemorySwap'] = self.memory_swap if self.memory_swap
        host_config['Privileged'] = self.privileged if self.privileged
        host_config['CapAdd'] = self.cap_add if self.cap_add && self.cap_add.size > 0
        host_config['CapDrop'] = self.cap_drop if self.cap_drop && self.cap_drop.size > 0

        log_opts = self.build_log_opts
        host_config['LogConfig'] = log_opts unless log_opts.empty?

        if self.devices && self.devices.size > 0
          host_config['Devices'] = self.build_device_opts
        end

        host_config
      end

      # @return [ServiceSpec]
      def data_volume_config
        {
          'Image' => self.image_name,
          'name' => "#{self.name}-volumes",
          'Entrypoint' => '/bin/sh',
          'Volumes' => self.build_volumes,
          'Cmd' => ['echo', 'Data only container'],
          'Labels' => {
            'io.kontena.container.name' => "#{self.name}-volumes",
            'io.kontena.container.pod' => self.name,
            'io.kontena.container.deploy_rev' => self.deploy_rev,
            'io.kontena.service.id' => self.labels['io.kontena.service.id'],
            'io.kontena.service.instance_number' => self.instance_number.to_s,
            'io.kontena.service.name' => self.labels['io.kontena.service.name'],
            'io.kontena.grid.name' => self.labels['io.kontena.grid.name'],
            'io.kontena.container.type' => 'volume'
          }
        }
      end

      ##
      # @return [Hash]
      def build_exposed_ports
        exposed_ports = {}
        self.ports.each do |p|
          exposed_ports["#{p['container_port']}/#{p['protocol']}"] = {}
        end
        exposed_ports
      end

      ##
      # @return [Hash]
      def build_port_bindings
        bindings = {}
        self.ports.each do |p|
          bindings["#{p['container_port']}/#{p['protocol']}"] = [{'HostPort' => p['node_port'].to_s}]
        end
        bindings
      end

      ##
      # @return [Hash]
      def build_volumes
        volumes = {}
        self.volumes.each do |vol|
          vol, _ = vol.split(':')
          volumes[vol] = {}
        end
        volumes
      end

      ##
      # @return [Array]
      def build_bind_volumes
        volumes = []
        self.volumes.each do |vol|
          volumes << vol if vol.include?(':')
        end
        volumes
      end

      # @return [Array<Hash>]
      def build_device_opts
        self.devices.map do |dev|
          host, container, perm = dev.split(':')
          {
            'PathOnHost' => host,
            'PathInContainer' => container || host,
            'CgroupPermissions' => perm || 'rwm'
          }
        end
      end

      ##
      # @return [Hash]
      def build_log_opts
        log_config = {}
        log_config['Type'] = self.log_driver if self.log_driver
        log_config['Config'] = {}
        if self.log_opts
          self.log_opts.each { |key, value|
            log_config['Config'][key.to_s] = value
          }
        end
        log_config
      end
    end
  end
end
