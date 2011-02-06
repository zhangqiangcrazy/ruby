#
# MVM sample driver for WEBrick
# By Urabe, Shyouhei.
#
# Copyright 2011 The University of Tokyo.
# Copyright 2011 the Network Applied Communication laboratory, inc.
#
# include it from your server class.
#

module WEBrick::MVMplugin
	if RubyVM.current.parent
		# child vm
		def start
			@logger.info "#{RubyVM.current.inspect} start"
			@status = :Running
			while @status == :Running do
				break unless a = RubyVM::ARGV[0].recv
				begin
					fd, ch = *a
					sock = TCPSocket.for_fd fd
					sock.do_not_reverse_lookup = config[:DoNotReverseLookup]
					ch.send true # pong
					addr = sock.peeraddr
					@logger.debug "dequeue #{sock.inspect} by #{RubyVM.current.inspect}"
					@logger.debug "accept: #{addr[3]}:#{addr[1]}"
					call_callback :AcceptCallback, sock
					run sock
				rescue Errno::ENOTCONN
					@logger.debug "Errno::ENOTCONN"
				rescue WEBrick::ServerError => ex
					msg = "#{ex.class}: #{ex.message}\n\t#{ex.backtrace[0]}"
					@logger.error msg
				rescue Exception => ex
					@logger.error ex
				ensure
					sock.close
				end
			end
		rescue SocketError
			@logger.debug "accept: <address unknown>"
			raise
		end

		def listen(*)
			# no need
		end
	else
		# parent vm
		def start
			nvms = $number_of_workers || 32
			file = $0
			@ch0 = RubyVM::Channel.new
			@ch1 = RubyVM::Channel.new
			@vms = Array.new nvms
			@vms.map! do
				vm = RubyVM.new "ruby", "-d", $0
				@logger.debug "starting #{vm.inspect}"
				vm.start @ch0
			end
			super
		end

		def start_thread sock
			@logger.debug "enqueue: #{sock.inspect}"
			@ch0.send [sock.fileno, @ch1]
			@ch1.recv # prevent GC to close file descriptor
			Thread.current
		end
	end
end

# convenient class
class WEBrick::MVMHTTPServer < WEBrick::HTTPServer
	include WEBrick::MVMplugin
end


# Local Variables:
# mode: ruby
# coding: utf-8
# indent-tabs-mode: t
# tab-width: 3
# ruby-indent-level: 3
# fill-column: 79
# default-justification: full
# End:
# vi: ts=3 sw=3
