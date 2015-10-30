require 'celluloid'
require_relative 'logging'
require_relative 'grid_scheduler'
require_relative 'load_balancer_configurer'

class GridServiceDeployer
  include Logging

  attr_reader :grid_service, :nodes, :scheduler, :config

  ##
  # @param [#find_node] strategy
  # @param [GridService] grid_service
  # @param [Array<HostNode>] nodes
  def initialize(strategy, grid_service, nodes, config = {})
    @scheduler = GridScheduler.new(strategy)
    @grid_service = grid_service
    @nodes = nodes
    @config = config
  end

  ##
  # Is deploy possible?
  #
  # @return [Boolean]
  def can_deploy?
    self.grid_service.container_count.times do |i|
      node = self.scheduler.select_node(self.grid_service, i, self.nodes)
      return false unless node
    end

    true
  end

  # @param [Hash] creds
  # @return [Celluloid::Future]
  def deploy_async(creds = nil)
    Celluloid::Future.new{ self.deploy(creds) }
  end

  ##
  # @param [Hash] creds
  def deploy(creds = nil)
    prev_state = self.grid_service.state
    info "starting to deploy #{self.grid_service.name}"
    self.grid_service.set_state('deploying')

    self.configure_load_balancer
    pulled_nodes = Set.new
    deploy_rev = Time.now.utc.to_s
    self.grid_service.container_count.times do |i|
      node = self.scheduler.select_node(self.grid_service, i, self.nodes)
      unless node
        raise "Cannot find applicable node for service instance #{self.grid_service.name}-#{i}"
      end

      unless pulled_nodes.include?(node)
        self.ensure_image(node, self.grid_service.image_name, creds)
        pulled_nodes << node
      end
      self.deploy_service_instance(node, (i + 1), deploy_rev)
    end

    self.grid_service.containers.where(:deploy_rev => {:$ne => deploy_rev}).each do |container|
      self.terminate_service_instance(container.host_node, container.name)
    end
    self.grid_service.set_state('running')

    true
  rescue RpcClient::Error => exc
    self.grid_service.set_state(prev_state)
    error "RPC error: #{exc.class.name} #{exc.message}"
    false
  rescue => exc
    self.grid_service.set_state(prev_state)
    error "Unknown error: #{exc.class.name} #{exc.message}"
    error exc.backtrace.join("\n") if exc.backtrace
    false
  end

  ##
  # @param [Hash] creds
  # @return [Celluloid::Future]
  def deploy_async(creds = nil)
    Celluloid::Future.new{ self.deploy(creds) }
  end

  ##
  # @param [HostNode] node
  # @param [String] image_name
  # @param [Hash] creds
  def ensure_image(node, image_name, creds = nil)
    image = image_puller(node, creds).pull_image(image_name)
    self.grid_service.update_attribute(:image_id, image.id)
  end

  ##
  # @param [HostNode] node
  # @param [Hash] creds
  def image_puller(node, creds = nil)
    Docker::ImagePuller.new(node, creds)
  end

  # @param [HostNode] node
  # @param [Integer] instance_number
  # @param [String] deploy_rev
  def deploy_service_instance(node, instance_number, deploy_rev)
    container_name = "#{self.grid_service.name}-#{instance_number}"
    old_container = self.grid_service.containers.find_by(name: container_name)
    if old_container && old_container.host_node && old_container.host_node != node
      self.terminate_service_instance(old_container.host_node, container_name)
      p "terminate old #{container_name}"
    end

    creator = Docker::ServiceCreator.new(self.grid_service, node)
    creator.create_service_instance(instance_number, deploy_rev)

    # node/agent has 60 seconds to do it's job
    Timeout.timeout(60) do
      sleep 0.5 until !self.grid_service.containers.find_by(name: container_name, deploy_rev: deploy_rev).nil?
      if self.config[:wait_for_port]
        sleep 0.5 until port_responding?(node, self.config[:wait_for_port])
      end
    end
  end

  # @param [HostNode] node
  # @param [String] instance_name
  def terminate_service_instance(node, instance_name)
    terminator = Docker::ServiceTerminator.new(node)
    terminator.terminate_service_instance(instance_name)
  end

  ##
  # @param [HostNode] node
  # @param [String] port
  def port_responding?(node, port)
    rpc_client = node.rpc_client(2)
    response = rpc_client.request('/agent/port_open?', container.network_settings[:ip_address], port)
    response['open']
  rescue RpcClient::Error
    return false
  end

  def configure_load_balancer
    load_balancers = self.grid_service.linked_to_load_balancers
    return if load_balancers.size == 0

    load_balancer = load_balancers[0]
    node = self.grid_service.grid.host_nodes.connected.first
    return unless node

    lb_conf = LoadBalancerConfigurer.new(
      node.rpc_client, load_balancer, self.grid_service
    )
    lb_conf.configure_async
  end
end
