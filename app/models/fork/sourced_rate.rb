# A rate with the source that observed it. It has the four members of
# Provider::ExchangeRateConcept::Rate plus `source`, so the importer, which
# reads rates by member name, passes the extra member through (design §4.6).
Fork::SourcedRate = Data.define(:date, :from, :to, :rate, :source)
