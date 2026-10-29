import DynamicKeys
import InterpolationKeys
import MixedKeys
import OwnerA
import OwnerB
import PlainKeys
import PrefixKeys

let argument = CommandLine.arguments.last ?? ""

_ = InterpolationKeysView(count: 3, name: argument, ratio: 0.5)
_ = DynamicKeysView(keyName: argument)
_ = MixedKeys.title(flag: argument.isEmpty, keyName: argument)
_ = PlainKeysView()
PlainKeyCalls.use()
_ = PrefixKeysView(suffix: argument)
_ = OwnerAView()
_ = OwnerBView(keyName: argument)
