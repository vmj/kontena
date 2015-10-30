require_relative 'common'

module GridServices
  class Create < Mutations::Command
    include Common

    required do
      model :current_user, class: User
      model :grid, class: Grid
      string :image
      string :name, matches: /^(?!-)(\w|-)+$/ # do not allow "-" as a first character
      boolean :stateful
    end

    optional do
      integer :container_count
      string :user
      integer :cpu_shares, min: 0, max: 1024
      integer :memory
      integer :memory_swap
      boolean :privileged
      array :cap_add do
        string
      end
      array :cap_drop do
        string
      end
      array :cmd do
        string
      end
      string :entrypoint
      array :env do
        string
      end
      string :net, matches: /^(bridge|host|container:.+)$/
      array :ports do
        hash do
          required do
            string :ip, default: '0.0.0.0'
            string :protocol, default: 'tcp'
            integer :node_port
            integer :container_port
          end
        end
      end
      array :links do
        hash do
          required do
            string :name
            string :alias
          end
        end
      end
      array :volumes do
        string
      end
      array :volumes_from do
        string
      end
      array :affinity do
        string
      end
      hash :log_opts do
        string :*
      end
      string :log_driver
      array :devices do
        string
      end
    end

    def validate
      if self.stateful && self.volumes_from && self.volumes_from.size > 0
        add_error(:volumes_from, :invalid, 'Cannot combine stateful & volumes_from')
      end
      if self.links
        self.links.each do |link|
          unless self.grid.grid_services.find_by(name: link[:name])
            add_error(:links, :not_found, "Service #{link[:name]} does not exist")
          end
        end
      end
    end

    def execute
      attributes = self.inputs.clone
      attributes.delete(:current_user)
      attributes[:image_name] = attributes.delete(:image)
      attributes.delete(:links)
      if self.links
        attributes[:grid_service_links] = build_grid_service_links(self.grid, self.links)
      end
      
      grid_service = GridService.new(attributes)
      unless grid_service.save
        grid_service.errors.each do |key, message|
          add_error(key, :invalid, message)
        end
      end

      grid_service
    end
  end
end
