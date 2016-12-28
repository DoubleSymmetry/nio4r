require "spec_helper"

RSpec.describe NIO::ByteBuffer do
  let(:capacity)       { 256 }
  let(:example_string) { "Testing 1 2 3..." }
  subject(:bytebuffer) { described_class.new(capacity) }

  describe "#initialize" do
    it "raises TypeError if given a bogus argument" do
      expect { described_class.new(:symbols_are_bogus) }.to raise_error(TypeError)
    end
  end

  describe "#clear" do
    it "clears the buffer" do
      bytebuffer << example_string
      bytebuffer.clear

      expect(bytebuffer.remaining).to eq capacity
    end
  end

  describe "#position" do
    it "defaults to zero" do
      expect(bytebuffer.position).to be_zero
    end
  end

  describe "#limit" do
    it "defaults to the buffer's capacity" do
      expect(bytebuffer.limit).to eq capacity
    end
  end

  describe "#capacity" do
    it "has the requested capacity" do
      expect(bytebuffer.capacity).to eq capacity
    end
  end

  describe "#remaining" do
    it "calculates the number of bytes remaining" do
      expect(bytebuffer.remaining).to eq capacity
      bytebuffer << example_string
      expect(bytebuffer.remaining).to eq(capacity - example_string.length)
    end
  end

  describe "#full?" do
    it "returns false when there is space remaining in the buffer" do
      expect(bytebuffer).not_to be_full
    end

    it "returns true when the buffer is full" do
      bytebuffer << "X" * capacity
      expect(bytebuffer).to be_full
    end
  end

  describe "#get" do
    it "reads zeroes from a newly initialized buffer" do
      expect(bytebuffer.get(capacity)).to eq("\0" * capacity)
    end

    it "advances position as data is read" do
      bytebuffer << "First"
      bytebuffer << "Second"
      bytebuffer << "Third"
      bytebuffer.flip

      expect(bytebuffer.position).to be_zero
      expect(bytebuffer.get(10)).to eq "FirstSecon"
      expect(bytebuffer.position).to eq 10
    end

    it "raises NIO::ByteBuffer::UnderflowError if there is not enough data in the buffer" do
      bytebuffer << example_string
      bytebuffer.flip

      expect { bytebuffer.get(example_string.length + 1) }.to raise_error(NIO::ByteBuffer::UnderflowError)
      expect(bytebuffer.get(example_string.length)).to eq example_string
    end
  end

  describe "#<<" do
    it "adds strings to the buffer" do
      bytebuffer << example_string
      expect(bytebuffer.position).to eq example_string.length
      expect(bytebuffer.limit).to eq capacity
    end

    it "raises NIO::ByteBuffer::OverflowError if the buffer is full" do
      bytebuffer << "X" * (capacity - 1)
      expect { bytebuffer << "X" }.not_to raise_error
      expect { bytebuffer << "X" }.to raise_error(NIO::ByteBuffer::OverflowError)
    end
  end

  describe "#flip" do
    it "flips the bytebuffer" do
      bytebuffer << example_string
      expect(bytebuffer.position).to eql example_string.length

      expect(bytebuffer.flip).to eq bytebuffer

      expect(bytebuffer.position).to be_zero
      expect(bytebuffer.limit).to eq example_string.length
      expect(bytebuffer.get(example_string.length)).to eq example_string
    end

    it "sets remaining to the previous position" do
      bytebuffer << example_string
      previous_position = bytebuffer.position
      expect(bytebuffer.remaining).to eq(capacity - previous_position)

      bytebuffer.flip
      expect(bytebuffer.remaining).to eq previous_position
    end

    it "sets limit to the previous position" do
      bytebuffer << example_string
      expect(bytebuffer.limit).to eql(capacity)

      previous_position = bytebuffer.position
      bytebuffer.flip
      expect(bytebuffer.limit).to eql previous_position
    end
  end

  describe "#rewind" do
    it "rewinds the buffer leaving the limit intact" do
      bytebuffer << example_string
      expect(bytebuffer.rewind).to eq bytebuffer

      expect(bytebuffer.position).to be_zero
      expect(bytebuffer.limit).to eq capacity
    end
  end

  describe "#mark" do
    it "returns self" do
      expect(bytebuffer.mark).to eql bytebuffer
    end
  end

  describe "#reset" do
    it "returns to a previously marked position" do
      bytebuffer << "First"
      expected_position = bytebuffer.position

      expect(bytebuffer.mark).to eq bytebuffer
      bytebuffer << "Second"
      expect(bytebuffer.position).not_to eq expected_position

      bytebuffer.reset
      expect(bytebuffer.position).to eq expected_position
    end

    it "raises NIO::ByteBuffer::MarkUnsetError unless mark has been set" do
      expect { bytebuffer.reset }.to raise_error(NIO::ByteBuffer::MarkUnsetError)
    end
  end

  describe "#inspect" do
    it "inspects the buffer offsets" do
      regex = /\A#<NIO::ByteBuffer:.*? @position=0 @limit=#{capacity} @capacity=#{capacity}>\z/
      expect(bytebuffer.inspect).to match(regex)
    end
  end

  context "I/O" do
    let(:addr)   { "127.0.0.1" }
    let(:port)   { 54_321 }
    let(:server) { TCPServer.new(addr, port) }
    let(:client) { TCPSocket.new(addr, port) }
    let(:peer)   { server_thread.value }

    let(:server_thread) do
      server

      thread = Thread.new { server.accept }
      Thread.pass while thread.status && thread.status != "sleep"

      thread
    end

    before do
      server_thread
      client
    end

    after do
      server_thread.kill if server_thread.alive?

      server.close rescue nil
      client.close rescue nil
      peer.close   rescue nil
    end

    describe "#read_from" do
      it "reads data into the buffer" do
        client.write(example_string)
        expect(bytebuffer.read_from(peer)).to eq example_string.length
        bytebuffer.flip

        expect(bytebuffer.get(example_string.length)).to eq example_string
      end

      it "raises NIO::ByteBuffer::OverflowError if the buffer is already full" do
        client.write(example_string)
        bytebuffer << "X" * capacity
        expect { bytebuffer.read_from(peer) }.to raise_error(NIO::ByteBuffer::OverflowError)
      end

      it "returns 0 if no data is available" do
        expect(bytebuffer.read_from(peer)).to eq 0
      end
    end

    describe "#write_to" do
      it "writes data from the buffer" do
        bytebuffer << example_string
        bytebuffer.flip

        expect(bytebuffer.write_to(client)).to eq example_string.length
        client.close

        expect(peer.read(example_string.length)).to eq example_string
      end

      it "raises NIO::ByteBuffer::UnderflowError if the buffer is out of data" do
        bytebuffer.flip
        expect { bytebuffer.write_to(peer) }.to raise_error(NIO::ByteBuffer::UnderflowError)
      end
    end
  end
end
