/*
 * MemTest.cpp
 *
 *  Created on: Nov 26, 2015
 *      Author: jcassidy
 */

#include <cinttypes>

#include <iomanip>
#include <iostream>

#include <array>

template<class Command>typename CommandTraits<Command>::Address address(const Command& cmd);




template<class Command>std::array<std::array<bool,N>,N> checkConflicts(const std::array<Command>& cmd)
{
	std::array<std::array<bool,N>,N> conflict;

	for(unsigned i=0;i<Np;++i)
		for(unsigned j=i+1;j<Np;++j)
			conflict[i][j] = conflict[j][i] = address(cmd[i]) == address(cmd[j]);
}



template<
	typename Address=uint32_t,
	typename Data=uint64_t,
	typename Time=uint64_t,
	typename Serial=uint32_t>
		class MultiPortCommandTrace
{
	struct Command
	{
		uint8_t		port;
		bool		write;
		Address		addr;
		Time		time;
		Data		data;

		friend std::ostream& operator<<(std::ostream& os,const Command& cmd)
		{
			auto fmt = os.flags();
			os << std::setw(8) << std::dec << cmd.time << ' ' << std::setw(1) << cmd.port << ' ' << (cmd.write ? 'W' : 'R') << std::setw(8)
				<< std::hex << cmd.addr << ' ' << std::setw(16) << cmd.data << std::endl;
			os.flags(fmt);
			return os;
		}

		friend std::istream& operator>>(std::istream& is,Command& cmd)
		{
			auto fmt = is.flags();
			char rw;
			is >> std::dec >> cmd.time >> cmd.port >> rw >> std::hex >> cmd.addr >> cmd.data >> std::endl;
			cmd.write = rw=='W';
			is.flags(fmt);
			return is;
		}
	};

	Serial logCommand(const Command& cmd)
	{
		Serial s = m_commands.size();
		m_commands.push_back(cmd);
		m_nReads  += !cmd.write;
		m_nWrites += cmd.write;
		return s;
	}

private:
	std::vector<Command>	m_commands;
	Serial					m_nReads=0;
	Serial					m_nWrites=0;
};

//	struct Response {
//		uint8_t			port;
//		uint64_t		time;
//		uint64_t		data;
//
//		friend std::ostream& operator<<(std::ostream& os,const Response& resp)
//		{
//			auto fmt=os.flags();
//			os << std::setw(8) << std::dec << resp.time << ' ' << std::setw(1) << resp.port << ' ' << std::setw(16) << resp.data << std::endl;
//			os.flags(fmt);
//			return os;
//		}
//
//		friend std::istream& operator>>(std::istream& is,Response& resp)
//		{
//			auto fmt = is.flags();
//			is >> std::dec >> resp.time >> resp.port >> std::hex >> resp.data >> std::endl;
//			is.flags(fmt);
//			return is;
//		}
//	};







#include <vector>
#include <fstream>
#include <array>
#include <iostream>
#include <iomanip>

#include <boost/range/adaptor/indexed.hpp>

using namespace std;

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
