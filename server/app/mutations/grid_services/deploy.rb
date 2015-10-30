require_relative '../../services/grid_service_deployer'

module GridServices
  class Deploy < Mutations::Command

    DEFAULT_REGISTRY = 'index.docker.io'
    STRATEGIES = {
        'ha' => Scheduler::Strategy::HighAvailability,
        'random' => Scheduler::Strategy::Random
    }.freeze

    class ExecutionError < StandardError
    end

    required do
      model :grid_service
      string :strategy, nils: true, default: 'ha'
    end

    optional do
      model :current_user, class: User
      integer :wait_for_port
    end

    def validate
      unless self.grid_service.grid.has_initial_nodes?
        add_error(:grid, :invalid_state, 'Grid does not have initial nodes ready')
        return
      end
      if self.grid_service.deploying?
        add_error(:service, :invalid_state, 'Service is currently deploying')
        return
      end
      unless STRATEGIES[self.strategy]
        add_error(:strategy, :invalid_strategy, 'Strategy not supported')
        return
      end

      if !deployer.can_deploy?
        add_error(:nodes, :too_few, 'Too few applicable nodes available')
      end
    end

    def execute
      deployer.deploy_async(creds_for_registry)

      self.grid_service
    end

    ##
    # @return [Hash,NilClass]
    def creds_for_registry
      registry = self.grid_service.grid.registries.find_by(name: self.registry_name)
      if registry
        registry.to_creds
      end
    end

    ##
    # @return [String]
    def registry_name
      return DEFAULT_REGISTRY unless self.grid_service.image_name.include?('/')

      name = self.grid_service.image_name.to_s.split('/')[0]
      if name.match(/(\.|:)/)
        name
      else
        DEFAULT_REGISTRY
      end
    end

    ##
    # @return [GridServiceDeployer]
    def deployer
      if @deployer.nil?
        nodes = self.grid_service.grid.host_nodes.connected.to_a
        strategy = STRATEGIES[self.strategy].new
        @deployer = GridServiceDeployer.new(strategy, self.grid_service, nodes, deploy_options)
      end

      @deployer
    end

    ##
    # @return [Hash]
    def deploy_options
      deploy_options = {}
      deploy_options[:wait_for_port] = self.wait_for_port if self.wait_for_port
      deploy_options
    end
  end
end
