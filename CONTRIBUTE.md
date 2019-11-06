# CONTRIBUTING

1. Follow the best practices as described [here](https://github.com/bahamas10/bash-style-guide)
2. When handling file-names, we use ```basename``` and ```dirname``` in stead of shell parameter expansion - as shell parameter expansion does not take into account windows vs POSIX path differences
3. Helper functions are functions which do not have a ```-h``` option available


## When Updating Attributes
Make sure ```git status``` returns
> "nothing to commit ..."
then run ```git checkout-index --force --all```