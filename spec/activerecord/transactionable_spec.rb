require "spec_helper"

describe Activerecord::Transactionable do
  it "has a version number" do
    expect(Activerecord::Transactionable::VERSION).not_to be nil
  end

  class FarOutError < StandardError; end

  class PlainVanillaIceCream
    include ActiveModel::Validations
    attr_accessor :topping
    validates_presence_of :topping
    def raise_something(*args)
      raise *args
    end
    def self.raise_something(*args)
      raise *args
    end
    def logger
      self.class.logger
    end
    def self.logger
      @logger ||= NullLogger.new
    end
  end

  class TransactionableIceCream < PlainVanillaIceCream
    include Activerecord::Transactionable
    def raise_something(*args)
      transaction_wrapper(rescued_errors: FarOutError) do
        super(*args)
      end
    end
    def self.raise_something(error:, object: nil, retriable_errors: nil, rescued_errors: FarOutError, reraisable_errors: nil)
      transaction_wrapper(object: object,
                          retriable_errors: retriable_errors,
                          rescued_errors: rescued_errors,
                          reraisable_errors: reraisable_errors) do
        super(error)
      end
    end
    def logger
      self.class.logger
    end
    def self.logger
      @logger ||= NullLogger.new
    end
  end

  describe Activerecord::Transactionable, :concerns do

    let(:record_invalid_error) { ActiveRecord::RecordInvalid.new(PlainVanillaIceCream.new) }

    context "for ActiveRecord::Rollback" do
      context "without concern" do
        it("raises") {
          expect {
            PlainVanillaIceCream.new.raise_something(ActiveRecord::Rollback)
          }.to raise_error ActiveRecord::Rollback
        }
      end
      context "with concern" do
        # NOTE: this spec tests default behavior of rails, but it is complicated, and confusing, and worth calling out in a spec.
        it("does not raise because swallowed by ActiveRecord's handling of the transaction") {
          expect {
            TransactionableIceCream.new.raise_something(ActiveRecord::Rollback)
          }.to_not raise_error
        }
        it("returns true") { # Because not re-raised
          expect(TransactionableIceCream.new.raise_something(ActiveRecord::Rollback)).to be true
        }
      end
    end

    context "for ActiveRecord::RecordInvalid" do
      context "without concern" do
        it("raises") {
          expect {
            PlainVanillaIceCream.new.raise_something(record_invalid_error)
          }.to raise_error ActiveRecord::RecordInvalid
        }
      end
      context "with concern" do
        let(:object) { TransactionableIceCream.new }
        it("does not raise") {
          expect {
            object.raise_something(record_invalid_error)
          }.to_not raise_error
        }
        it("returns false") { expect(object.raise_something(record_invalid_error)).to be false }
        it("adds error to base") {
          object.valid?
          error = ActiveRecord::RecordInvalid.new(object)
          object.raise_something(error)
          expect(object.errors.full_messages).to eq ["Topping can't be blank"]
        }
        it("logs error") {
          expect(TransactionableIceCream.logger).to receive(:error).with("[TransactionableIceCream.transaction_wrapper] On TransactionableIceCream FarOutError: FarOutError")
          TransactionableIceCream.raise_something(error: FarOutError, object: object)
        }
      end
    end

    context "for any error that needs handling" do
      context "without concern" do
        it("raises") {
          expect {
            PlainVanillaIceCream.new.raise_something(FarOutError)
          }.to raise_error FarOutError
        }
      end
      context "with concern" do
        context "instance level" do
          it("does not raise") {
            expect {
              TransactionableIceCream.new.raise_something(FarOutError)
            }.to_not raise_error
          }
          it("returns false") { expect(TransactionableIceCream.new.raise_something(FarOutError)).to be false }
          it("adds error to base") {
            ice_cream = TransactionableIceCream.new
            ice_cream.raise_something(FarOutError)
            expect(ice_cream.errors.full_messages).to eq ["FarOutError"]
          }
        end
        context "class level" do
          context "with object provided" do
            let(:object) { TransactionableIceCream.new }
            it("does not raise") {
              expect {
                TransactionableIceCream.raise_something(error: FarOutError, object: object)
              }.to_not raise_error
            }
            it("returns false") { expect(TransactionableIceCream.raise_something(error: FarOutError, object: object)).to be false }
            it("adds error to base") {
              TransactionableIceCream.raise_something(error: FarOutError, object: object)
              expect(object.errors.full_messages).to eq ["FarOutError"]
            }
            it("logs error") {
              expect(TransactionableIceCream.logger).to receive(:error).with("[TransactionableIceCream.transaction_wrapper] On TransactionableIceCream FarOutError: FarOutError")
              TransactionableIceCream.raise_something(error: FarOutError, object: object)
            }
          end
          context "no object provided" do
            it("does not raise") {
              expect {
                TransactionableIceCream.raise_something(error: FarOutError, object: nil)
              }.to_not raise_error
            }
            it("returns false") { expect(TransactionableIceCream.raise_something(error: FarOutError, object: nil)).to be false }
            it("logs error") {
              expect(TransactionableIceCream.logger).to receive(:error).with("[TransactionableIceCream.transaction_wrapper] FarOutError: FarOutError")
              TransactionableIceCream.raise_something(error: FarOutError, object: nil)
            }
          end
          context "retriable" do
            it("does not raise") {
              expect {
                TransactionableIceCream.raise_something(error: FarOutError, object: nil, retriable_errors: FarOutError)
              }.to_not raise_error
            }
            it("returns false") { expect(TransactionableIceCream.raise_something(error: FarOutError, object: nil, retriable_errors: FarOutError)).to be false }
            it("logs both attempts") {
              expect(TransactionableIceCream.logger).to receive(:error).with("[TransactionableIceCream.transaction_wrapper] FarOutError: FarOutError [1st attempt]").once
              expect(TransactionableIceCream.logger).to receive(:error).with("[TransactionableIceCream.transaction_wrapper] FarOutError: FarOutError [2nd attempt]").once
              TransactionableIceCream.raise_something(error: FarOutError, object: nil, retriable_errors: FarOutError)
            }
          end
          context "reraisable" do
            it("raises") {
              expect {
                TransactionableIceCream.raise_something(error: FarOutError, object: nil, reraisable_errors: FarOutError)
              }.to raise_error FarOutError
            }
            it("logs error") {
              expect(TransactionableIceCream.logger).to receive(:error).with("[TransactionableIceCream.transaction_wrapper] FarOutError: FarOutError [re-raising!]").once
              expect {
                TransactionableIceCream.raise_something(error: FarOutError, object: nil, reraisable_errors: FarOutError)
              }.to raise_error FarOutError
            }
          end
        end
      end
    end

  end
end
