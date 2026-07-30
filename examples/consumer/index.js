// The bun half of the integration test. It calls into its one dependency on
// purpose: an install that produced an unusable `node_modules` still satisfies
// `test -d node_modules`, so the check has to run the thing.
import ms from "ms";

console.log(`nivis bun ok ${ms(60000)}`);
