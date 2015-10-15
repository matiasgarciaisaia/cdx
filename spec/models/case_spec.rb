require 'spec_helper'

describe Case do

  it "should make a case from a test" do
    kase = Case.make(:test_result)
    expect(kase).to be_valid
    expect(kase.source).to be_kind_of(TestResult)
  end

  it "should make a case from a sample" do
    kase = Case.make(:sample)
    expect(kase).to be_valid
    expect(kase.source).to be_kind_of(Sample)
  end

  it "should make a case from an encounter" do
    kase = Case.make(:encounter)
    expect(kase).to be_valid
    expect(kase.source).to be_kind_of(Encounter)
  end

end
