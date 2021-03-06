require 'hook_lying_syncer'

describe HookLyingSyncer do

  describe "on instances" do

    before do
      @person = Person.new("Dave")
      kinds_getter = lambda_maker("find_", "_", "_widgets")
      @syncer = HookLyingSyncer.new(@person, kinds_getter) do |p, kinds, *args|
        addons = args.any? ? ", with #{args.join(" and ")}" : nil
        "#{p.name} wants #{kinds.join(" ")} widgets#{addons}"
      end
    end

    describe "respond_to_missing?" do

      it "can handle dynamically defined methods" do
        expect(@syncer.respond_to? :find_green_widgets).to equal true
      end

      it "can handle the original object's methods" do
        expect(@syncer.respond_to? :name).to equal true
      end

      it "still rejects unknown methods" do
        expect(@syncer.respond_to? :blargh).to equal false
      end

    end

    describe "method_missing" do

      describe "can handle dynamically defined methods" do

        it "with no args" do
          expect(@syncer.find_green_widgets).to eql "Dave wants green widgets"
        end

        it "with an arg" do
          expect(@syncer.find_green_widgets(:stripes)).to eql(
            "Dave wants green widgets, with stripes")
        end

        it "with multiple args" do
          expect(@syncer.find_green_widgets(:stripes, :spots)).to eql(
            "Dave wants green widgets, with stripes and spots")
        end

        it "with multiple subparts" do
          expect(@syncer.find_big_green_widgets).to eql(
            "Dave wants big green widgets")
        end

      end

      describe "can handle the object's original methods" do

        it "using the original object" do
          expect(@syncer.name).to eql "Dave"
        end

        it "even if the object-pointing var is changed" do
          @person = Person.new("Chris")
          expect(@person.name).to eql "Chris" # just a sanity check
          expect(@syncer.name).to eql "Dave"
        end

      end

      it "doesn't prevent blowup on totally unknown methods" do
        expect { @syncer.blarg }.to raise_error NoMethodError
      end

      it "can add methods" do
        method_matcher = lambda { |name| name == :foo ? [name] : nil }
        syncer = HookLyingSyncer.new(@person, method_matcher) do |p, wants, *args|
          :foo
        end
        expect(syncer.foo).to equal :foo
      end

      it "can override methods" do
        method_matcher = lambda { |name| name == :name ? [name] : nil }
        syncer = HookLyingSyncer.new(@person, method_matcher) do |p, wants, *args|
          p.name.reverse.capitalize
        end
        expect(syncer.name).to eql "Evad"
      end

    end

    describe "with multiple levels" do

      before do
        name_getter = lambda_maker("say_to_", "_and_")
        @inner = @syncer
        @outer = HookLyingSyncer.new(@inner, name_getter) do |inner, names, *args|
          "#{inner.name} says \"#{args.join("\" and \"")}\" to #{names.map(&:capitalize).join(" and ")}"
        end
      end

      describe "respond_to_missing?" do

        it "can handle dynamically defined methods" do
          expect(@person.respond_to? :say_to_fred).to equal false
          expect(@inner.respond_to? :say_to_fred).to equal false
          expect(@outer.respond_to? :say_to_fred).to equal true
        end

        it "can handle the original object's methods" do
          expect(@outer.respond_to? :name).to equal true
        end

        it "still rejects unknown methods" do
          expect(@outer.respond_to? :blargh).to equal false
        end

      end

      describe "method_missing" do

        it "can handle dynamically defined methods" do
          expect(@outer.say_to_fred_and_ethel("hail", "well met")).to eql(
            "Dave says \"hail\" and \"well met\" to Fred and Ethel")
        end

        it "can handle the inner object's methods" do
          expect(@outer.name).to eql "Dave"
        end

        it "can handle the inner syncer's methods" do
          expect(@outer.find_big_green_widgets(:stripes, :spots)).to eql(
            "Dave wants big green widgets, with stripes and spots")
        end

        it "still barfs on unknown methods" do
          expect { @outer.blarg }.to raise_error NoMethodError
        end

      end

    end

  end

  describe "can wrap classes" do

    before do
      wants_getter = lambda_maker("find_by_", "_and_")
      @syncer = HookLyingSyncer.new(Person, wants_getter) do |c, wants, *args|
        if wants.length != args.length
          raise "#{wants.length} qualities but #{args.length} values"
        end
        # can't use to_h prior to ruby 2.0
        c.find to_hash_kluge(wants.zip(args))
      end
    end

    it "and receive method-name-parts and args" do
      expect(@syncer.find_by_eyes_and_hair_and_skin(:red, :blue, :green)).to eql(
        "Looking for a person with red eyes, blue hair, and green skin")
    end

    it "to override class methods" do
      method_matcher = lambda { |name| name == :what_are_they ? [name] : nil }
      what_they_are = "three little maids from school"
      syncer = HookLyingSyncer.new(Person, method_matcher) do |c, wants, *args|
        what_they_are
      end
      expect(syncer.what_are_they).to eql what_they_are
    end

    it "to add class methods" do
      method_matcher = lambda { |name| name == :foo ? [name] : nil }
      syncer = HookLyingSyncer.new(Person, method_matcher) do |c, wants, *args|
        :foo
      end
      expect(syncer.foo).to equal :foo
    end

    it "to override the class's .new method" do
      method_matcher = lambda { |name| name == :new ? [name] : nil }
      syncer = HookLyingSyncer.new(Person, method_matcher) do |c, wants, *args|
        c.new(args[0].reverse.capitalize)
      end
      expect(syncer.new("Dave").name).to eql "Evad"
    end

    it "to add instance methods" do
      method_matcher = lambda { |name| name == :new ? [name] : nil }
      syncer = HookLyingSyncer.new(Person, method_matcher) do |c, wants, *args|
        c.new(args).tap { |obj|
          def obj.foo
            :foo
          end
        }
      end
      expect(syncer.new("Dave").foo).to equal :foo
    end

    it "can still call the class's methods" do
      expect(@syncer.what_are_they).to eql Person.what_are_they
    end

    describe "wrapping an already wrapped class" do

      before do
        needs_getter = lambda_maker("need_with_", "_and_")
        @outer = HookLyingSyncer.new(@syncer, needs_getter) do |c, wants, *args|
          # can't use to_h prior to ruby 2.0
          c.need to_hash_kluge(wants.zip(args))
        end
      end

      it "can call the new thing" do
        expect(@outer.need_with_eyes_and_hair(:red, :blue)).to eql(
          "I need a person with red eyes and blue hair")
      end

      it "can still call the old thing" do
        expect(@outer.find_by_eyes_and_hair(:red, :blue)).to eql(
          "Looking for a person with red eyes and blue hair")
      end

      it "can still call the class's methods" do
        expect(@syncer.what_are_they).to eql Person.what_are_they
      end

    end

  end

end

private

def lambda_maker(prefix, separator, suffix=nil)
  lambda { |method_name|
    matches = /\A#{prefix}(\w+)#{suffix}\Z/.match(method_name.to_s)
    matches[1].split(separator) if matches
  }
end

class Person

  attr_reader :name

  def initialize(name)
    @name = name
  end

  def self.find(params)
    self.seek("Looking for", params)
  end

  def self.need(params)
    self.seek("I need", params)
  end

  def self.what_are_they
    "Are we not men?  We are Devo!  D-E-V-O!"
  end

  private

  def self.seek(look_how, params)
    wants = [].tap { |list| params.each { |key, val| list << "#{val} #{key}" } }

    # there's got to be some way to do this more cleanly...
    # wouldn't be surprised if Rails has something like Array#sentencize....
    wants[-1] = "and #{wants[-1]}" if wants.length > 1
    separator = wants.length > 2 ? ", " : " "
    description = wants.join(separator)

    "#{look_how} a person with #{ description }"
  end

end

# since we can't use .to_h prior to ruby 2.0,
# and we want this gem to be usable w/ 1.8 and 1.9
def to_hash_kluge(ary)
  hash = {}
  ary.each { |pair| hash[pair.first] = pair.last }
  hash
end
