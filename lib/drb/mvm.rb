# See lib/drb/drb.rb for the DRb's socket API.

#
# MVM's high bandwidth RPC infrastructure.
#
# channel = RubyVM::Channel.new
# child = RubyVM.new("ruby", "-rdrb/mvm")
# child.start channel
# DRb.start_server ivcc, self
#

require 'drb'

class RubyVM::DRbSocket
  def self.parse_uri uri
    case uri when /\Adrbmvm:/ then
      return eval($')
    else
      raise DRb::DRbBadScheme, uri
    end
  end

  def self.uri_option uri, config
    return uri, nil
  end

  def self.open uri, config
    ch = parse_uri uri
    tx = RubyVM::Channel.new
    rx = RubyVM::Channel.new
    ch.send [rx, tx]
    return RubyVM::DRbSocket::DRbConnection.new rx, tx, config
  rescue TypeError
    raise DRb::DRbBadScheme, "uri broken: #{uri}"
  end

  def self.open_server uri, config
    ch = parse_uri uri
    return RubyVM::DRbSocket::DRbListener.new uri, ch, config
  end
end

class RubyVM::DRbSocket::DRbListener
  def initialize uri, ch, config
    @uri = uri
    @ch = ch
  end

  def accept
    tx, rx = *@ch.recv
    return RubyVM::DRbSocket::DRbConnection.new rx, tx, nil    
  end

  def close
    # nothing
  end

  def uri
    @uri
  end
end

class RubyVM::DRbSocket::DRbConnection
  def initialize rx, tx, config
    @rx = rx
    @tx = tx
  end

  private
  def recursive_encode obj
    case obj
    when Fixnum, Symbol, TrueClass, FalseClass, NilClass, RubyVM::Channel
      return obj
    when Array
      tmp = obj.map do |i|
        recursive_encode i
      end
      return :Array, tmp
    when String
      return :String, obj
    else
      obj = DRbObject.new(obj) if obj.kind_of? DRbUndumped
      begin
	str = Marshal.dump obj
      rescue
	str = Marshal.dump DRbObject.new(obj)
      end
      return :else, str
    end
  end

  def recursive_decode obj
    case obj
    when Fixnum, Symbol, TrueClass, FalseClass, NilClass, RubyVM::Channel
      return obj
    when Array
      case obj[0]
      when :Array
        ret = obj[1].map do |i|
          recursive_decode i
        end
        return ret
      when :String
        return obj[1]
      when :else
        ret = Marshal.load obj[1]
        return ret
      end
    end
    raise DRbConnError, "broken."
  end

  public
  def send_request *argv
    argv[0] = argv[0].__drbref
    arge = recursive_encode argv
    @tx.send arge
  end

  def recv_request
    arge = *@rx.recv
    argv = recursive_decode arge
    argv[0] = DRb.to_obj argv[0]
    return *argv
  end

  def send_reply *argv
    arge = recursive_encode argv
    @tx.send arge
  end

  def recv_reply
    arge = @rx.recv
    argv = recursive_decode arge
    return *argv
  end

  def alive?
    not not (@tx and @rx)
  end

  def close
    # leave GC to finish the channels.
    @tx = @rx = nil
  end
end

DRb::DRbProtocol.add_protocol RubyVM::DRbSocket
