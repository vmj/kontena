class DistributedLock
  include Mongoid::Document

  field :name, type: String
  field :lock_id, type: String
  field :created_at, type: DateTime

  index({ name: 1 }, { unique: true })

  # @param [String] name
  # @param [Integer] timeout
  def self.with_lock(name, timeout = 60)
    lock_id = nil
    begin
      Timeout.timeout(timeout) do
        sleep 0.01 until lock_id = self.obtain_lock(name)
      end
      return yield
    rescue Timeout::Error
      return false
    ensure
      self.release_lock(name, lock_id) if lock_id
    end
  end

  # @param [String] name
  # @return [String, FalseClass]
  def self.obtain_lock(name)
    lock_id = SecureRandom.hex(16)
    query = {name: name, lock_id: {:$exists => false}}
    modify = {'$set' => {name: name, lock_id: lock_id, created_at: Time.now.utc}}
    lock = nil
    begin
      lock = where(query).find_and_modify(modify, {upsert: true, new: true})
    rescue Moped::Errors::OperationFailure
    end
    if lock && lock.lock_id == lock_id
      lock_id
    else
      false
    end
  end

  # @param [String] name
  # @param [String] lock_id
  def self.release_lock(name, lock_id)
    where(name: name, lock_id: lock_id).destroy
  end
end