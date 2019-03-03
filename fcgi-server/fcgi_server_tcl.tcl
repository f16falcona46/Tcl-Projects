package require fcgi
package require sqlite3
package require rest
package require http
package require Thread

set curdir [file dirname [info script]]

source [file join $curdir "TemplaTcl.tcl"]

fcgi Init
set sock [fcgi OpenSocket :8000]
set req [fcgi InitRequest $sock 0]
sqlite3 sitedb [file join $curdir "sites.db"]

set templates [dict create]

#CalHacks 2018
sqlite3 clientsDb [file join $curdir "clients.db"]
clientsDb eval {CREATE TABLE IF NOT EXISTS Clients (Id INTEGER NOT NULL UNIQUE, DoorOpen INTEGER, PRIMARY KEY(Id));}
#END CalHacks 2018
#Hacktech 2019
proc do_nothing_callback {} {}
set thread_job {
	http::geturl "http://127.0.0.1:8080$request_str"
	thread::wait
}
set background_t [thread::create -preserved]
thread::send $background_t {package require http}
sqlite3 sound_sensorsDb [file join $curdir "sound_sensors.db"]
#END Hacktech 2019

while {1} {
	fcgi Accept_r $req
	#get the requested page
	set pd [fcgi GetParam $req]
	set request_str [dict get $pd REQUEST_URI]
	if {$request_str eq "/"} {
		set request_str "/cgi-bin/getpage.cgi?p=1"
	}
	if {[dict get $pd DOCUMENT_URI] eq "/"} {
		set webapp "getpage.cgi"
	} else {
		set webapp [split [dict get $pd DOCUMENT_URI] "/"]
		set webapp [lindex $webapp [expr [llength $webapp] - 1]]
	}
	set query_params [rest::parameters $request_str]
	if {$webapp eq "getpage.cgi"} {
		if [dict exists $query_params p] {
			set id [dict get $query_params p]
			#generate the page
			set C "Status: 200 OK\n"
			set page [sitedb eval {SELECT Name,ID,Content,Template,ContentType,Parent FROM Pages WHERE ID=$id ORDER BY Version DESC;}]
			if {$page ne ""} {
				append C "Content-Type: "
				append C [lindex $page 4]
				append C "\r\n\r\n"
				set TemplateID [lindex $page 3]
				if $TemplateID {
					if {![dict exists $templates $TemplateID]} {
						set template "TEMPLATE_OBJ_$TemplateID"
						TemplaTcl::create $template
						dict append templates $TemplateID $template
						$template parse [lindex [sitedb eval {SELECT TemplateText FROM Templates WHERE ID=$TemplateID;}] 0]
					} else {
						set template [dict get $templates $TemplateID]
					}
					$template setVar NAME [lindex $page 0]
					$template setVar ID [lindex $page 1]
					$template setVar CONTENT [lindex $page 2]
					$template setVar TEMPLATE [lindex $page 3]
					$template setVar CONTENTTYPE [lindex $page 4]
					$template setVar PARENT [lindex $page 5]
					append C [$template render]
				} else {
					append C [lindex $page 2]
				}
			} else {
				set C "Status: 200 OK\n"
				append C "Page not found. Query: "
				append C [dict get $pd REQUEST_URI]
			}
		} else {
			set C "Status: 200 OK\n"
			append C "Invalid query. Query: "
			append C [dict get $pd REQUEST_URI]
		}
	} elseif {$webapp eq "webapp.cgi"} {
		#CalHacks 2018
		set C "Status: 200 OK\n"
		append C "Content-Type: "
		append C "text/html"
		append C "\r\n\r\n"
		if {[dict exists $query_params "action"]} {
			if {[dict get $query_params "action"] eq "add_sensor"} {
				set id [expr {int(1000000 * rand())}]
				clientsDb eval {INSERT INTO Clients (Id, DoorOpen) VALUES ($id, 0);}
				append C [format "%06d" $id]
			} elseif {[dict get $query_params "action"] eq "door_open"} {
				if [dict exists $query_params "id"] {
					set id [dict get $query_params "id"]
					clientsDb eval {UPDATE Clients SET DoorOpen=1 WHERE Id=$id;}
				} else {
					append C "Parameter id is missing."
				}
			} elseif {[dict get $query_params "action"] eq "door_close"} {
				if [dict exists $query_params "id"] {
					set id [dict get $query_params "id"]
					clientsDb eval {UPDATE Clients SET DoorOpen=0 WHERE Id=$id;}
				} else {
					append C "Parameter id is missing."
				}
			} elseif {[dict get $query_params "action"] eq "is_door_open"} {
				if [dict exists $query_params "id"] {
					set id [dict get $query_params "id"]
					append C [clientsDb eval {SELECT DoorOpen FROM Clients WHERE Id=$id;}]
				} else {
					append C "Parameter id is missing."
				}
			}
		} else {
			append C "Parameter action is missing."
		}
		#END CalHacks 2018
	} elseif {$webapp eq "hacktech2019.cgi"} {
		#Hacktech 2019
		set C "Status: 200 OK\n"
		append C "Content-Type: "
		append C "text/html"
		append C "\r\n\r\n"
		
		append C "$request_str"
		thread::send -async $background_t "set request_str {$request_str}"
		thread::send -async $background_t $thread_job
	} elseif {$webapp eq "hacktech2019_return.cgi"} {
		set C "Status: 200 OK\n"
		append C "Content-Type: "
		append C "text/html"
		append C "\r\n\r\n"
		
		set db_response [sound_sensorsDb eval {SELECT Lat, Lon FROM Events ORDER BY T DESC LIMIT 1;}]
		append C [lindex $db_response 0]
		append C ","
		append C [lindex $db_response 1]
		#END Hacktech 2019
	} else {
		set C "Status: 200 OK\n"
		append C "Invalid query. Query: "
		append C [dict get $pd REQUEST_URI]
	}
	#output the page
	fcgi PutStr $req stdout $C
	fcgi SetExitStatus $req stdout 0
	fcgi Finish_r $req
}
