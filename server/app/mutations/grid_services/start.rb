module GridServices
  class Start < Mutations::Command
    required do
      model :current_user, class: User
      model :grid_service
    end

    def execute
      prev_state = self.grid_service.state
      begin
        self.grid_service.set_state('starting')
        Celluloid::Future.new{
          self.start_service_instances
        }
        self.grid_service.set_state('running')
      rescue => exc
        self.grid_service.set_state(prev_state)
        raise exc
      end
    end

    def start_service_instances
      self.grid_service.containers.scoped.each do |container|
        Docker::ServiceStarter.new(container.host_node).start_service_instance(container.name)
      end
    end
  end
end
