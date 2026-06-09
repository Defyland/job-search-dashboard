require "test_helper"

class JobContractTypeClassifierTest < ActiveSupport::TestCase
  test "classifies contractor as PJ from high signal fields" do
    contract_type = JobContractTypeClassifier.call(
      title: "Senior React Engineer",
      raw_payload: { employmentType: "contractor" }
    )

    assert_equal "pj", contract_type
  end

  test "classifies employer as CLT from high signal fields" do
    contract_type = JobContractTypeClassifier.call(
      title: "Senior Ruby Engineer",
      raw_payload: { contract_metadata: { hiringType: "employer" } }
    )

    assert_equal "clt", contract_type
  end

  test "classifies mixed CLT and PJ regimes" do
    contract_type = JobContractTypeClassifier.call(
      title: "Desenvolvedor Front-end React Sênior",
      raw_payload: { source_payload: { regime: "CLT ou PJ" } }
    )

    assert_equal "clt_or_pj", contract_type
  end

  test "uses explicit description contract text without treating generic contract words as PJ" do
    explicit_pj = JobContractTypeClassifier.call(
      title: "Senior Rails Engineer",
      raw_payload: { description: "Contratacao PJ para atuar remoto." }
    )
    generic_contract = JobContractTypeClassifier.call(
      title: "Senior Solidity Engineer",
      raw_payload: { description: "Build smart contracts with React dashboards." }
    )

    assert_equal "pj", explicit_pj
    assert_equal "unknown", generic_contract
  end

  test "does not classify CLT from benefits alone" do
    contract_type = JobContractTypeClassifier.call(
      title: "Senior Ruby Engineer",
      raw_payload: { benefits: [ "Plano de saude", "Caju", "Gympass" ] }
    )

    assert_equal "unknown", contract_type
  end
end
