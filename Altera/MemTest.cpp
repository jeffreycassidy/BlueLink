/*
 * MemTest.cpp
 *
 *  Created on: Nov 26, 2015
 *      Author: jcassidy
 */



/** Tests a memory
 *
 * Input file (just one): contains lines of memory access commands, either a read or a write:
 * 		<time> <addr> R<port#>
 * 		<time> <addr> W<port#> data
 *
 * Output file contains results:
 * 		<time> <port#> <data>
 */

#include <cinttypes>

struct Command {
	uint64_t 	t;
	uint64_t	addr;
	uint64_t	data;
	unsigned	port;
	bool 		write;
};

struct Response {
	uint64_t	t;
	unsigned	port;
	uint64_t	data;
};

#include <vector>
#include <fstream>
#include <array>
#include <iostream>
#include <iomanip>

#include <boost/range/adaptor/indexed.hpp>

using namespace std;

vector<Command> loadCommands(const string fn);
vector<Response> loadResponses(const string fn);

int main(int argc,char **argv)
{
	const unsigned N=16;

	const unsigned NPorts=2;

	vector<Command> 	cmds	= loadCommands("m20k.stim.txt");
	vector<Response> 	resps 	= loadResponses("m20k.out.txt");

	array<vector<Response>::const_iterator,NPorts> portRespIt;

	// set up each port's response iterator to point at the first response for that port
	for(unsigned i=0;i<NPorts;++i)
		for(portRespIt[i] = resps.begin(); portRespIt[i] != resps.end() && portRespIt[i]->port != i; ++portRespIt[i]){}

	vector<uint64_t> v(N,0);		// memory contents

	size_t Nread=0, Nwrite=0;

	for(vector<Command>::const_iterator cmdIt = cmds.begin(); cmdIt != cmds.end(); ++cmdIt)
	{
		assert (cmdIt->addr < N);		// check address & port number within valid range
		assert (cmdIt->port < NPorts);

		if (cmdIt->write)
		{
			v[cmdIt->addr] = cmdIt->data;
			++Nwrite;
		}
		else
		{
			++Nread;
			if (portRespIt[cmdIt->port] == resps.end())
				cout << "ERROR: Missing expected response for command " << dec << (cmdIt-cmds.begin()) <<
				" (read issued at time " << dec << cmdIt->t << " for address " << hex << cmdIt->addr << ")" << endl;
			else
			{
				if (portRespIt[cmdIt->port]->data != v[cmdIt->addr])
				{
					// make sure the iterator for this port's responses is pointing the right place
					assert(portRespIt[cmdIt->port]->port == cmdIt->port);
					cout << "ERROR: Incorrect response for port " << dec << cmdIt->port << " at time " << portRespIt[cmdIt->port]->t << " expecting " << hex << v[cmdIt->addr] << " but got " << portRespIt[cmdIt->port]->data << endl;

					unsigned N=0;

					cout << "  Previous commands for address: " << endl;
					for(vector<Command>::const_iterator it=cmdIt; N < 6 && it != cmds.begin(); --it)
					{
						if (it->addr == cmdIt->addr)
						{
							++N;
							cout << "    time " << dec << setw(6) << it->t << " port " << it->port << " " << hex << setw(6) << it->addr << ' ';
							if (it->write)
								cout << " write " << it->data;
							else
								cout << " read";
							cout << endl;
						}
					}
					cout << endl << endl;

					cout << "  Previous commands:" << endl;
					for(vector<Command>::const_iterator it=cmdIt; N < 8 && (it--) != cmds.begin();)
					{
						++N;
						cout << "    time " << dec << setw(6) << it->t << ' ' << hex << setw(6) << it->addr << ' ';
						if (it->write)
							cout << " write " << it->data;
						else
							cout << " read";
						cout << endl;
					}
					cout << endl << endl;
				}

				// advance to the next response on this port
				portRespIt[cmdIt->port]++;
				while(portRespIt[cmdIt->port] != resps.end() && portRespIt[cmdIt->port]->port != cmdIt->port)
					++portRespIt[cmdIt->port];
			}

		}
	}

	assert(Nread+Nwrite==cmds.size());
	cout << "Processed " << dec << cmds.size() << " commands (" << Nread << " reads/" << Nwrite << " writes)" << endl;
}

vector<Command> loadCommands(const string fn)
{
	vector<Command> cmd;

	uint64_t t,addr,data;
	char op,p;
	unsigned port;

	ifstream is(fn.c_str());
	while (!is.eof())
	{
		is >> dec >> t >> hex >> p >> port >> op >> addr;
		assert(p=='P');
		if (op == 'W')
			is >> data;
		else
			data=0;
		cmd.push_back(Command { t, addr, data, port, op=='W' });
	}

	return cmd;
}

vector<Response> loadResponses(const string fn)
{
	vector<Response> resp;

	uint64_t t,data;
	unsigned port;
	char p;
	ifstream is(fn.c_str());

	while(!is.eof())
	{
		is >> dec >> t >> p >> port >> hex >> data;
		assert(p == 'P');
		resp.push_back(Response { t, port, data } );
	}

	return resp;
}
