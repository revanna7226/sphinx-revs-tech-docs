Struct in Go
-------------

Struct is a datastructure in Go. Collection of properties that are related togethet.

.. code-block:: go

    package main

    // defining a struct in go
    type person struct {
        firstName string
        lastname string
    }

    func main() {

        // creating struct values
        // Option #1
        alex := person{"Alex", "Anderson"}

        // Option #2
        alex := person{firstName:"Alex", lastname:"Anderson"}

        fmt.Println(alex) // {Alex Anderson}



    }


