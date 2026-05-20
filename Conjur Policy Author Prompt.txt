
Write Conjur policy-as-code to allow only identities in namespace "demo" to request certificates.
Allowed SAN pattern: spiffe://demo/<service-name>
Max TTL 4 hours.
Include 2 negative test cases (forbidden SAN and wrong namespace).
Return: policy/conjur.yml and policy/test_cases.md

