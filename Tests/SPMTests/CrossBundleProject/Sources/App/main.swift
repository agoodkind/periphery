import Foundation
import Lookup
import Owner

print(lookup("dynamic.used", bundle: ownerBundle))
print(localLookup("used"))
print("Main bundle: \(Bundle.main.bundlePath)")
print("Owner bundle: \(ownerBundle.bundlePath)")
print(Bundle.main.localizedString(forKey: "main." + CommandLine.arguments.last!, value: nil, table: nil))
